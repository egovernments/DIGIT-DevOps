#!/usr/bin/env python3
"""Gate for the tag-bump auto-merge workflow.

Compares each given env file between the PR base and the PR head and
requires that the only differences are scalar values at a path ending in
image.tag or image.repository (at any nesting depth, e.g. also under
initContainers.<name>.image.*) for service keys that already existed on
the base. Any added/removed key, or a change anywhere else, marks the PR
unsafe to auto-merge and leaves it for a human/code-owner review instead.
"""
import argparse
import os
import subprocess
import sys

import yaml

ALLOWED_LEAF_SUFFIXES = (("image", "tag"), ("image", "repository"))


def load_ref_file(ref, path):
    try:
        content = subprocess.check_output(["git", "show", f"{ref}:{path}"], text=True)
    except subprocess.CalledProcessError:
        return None
    return yaml.safe_load(content) or {}


def load_file(path):
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        return yaml.safe_load(f) or {}


def leaf_is_allowed(path_tuple):
    return len(path_tuple) >= 2 and path_tuple[-2:] in ALLOWED_LEAF_SUFFIXES


def diff_dicts(old, new, path=()):
    old = old if isinstance(old, dict) else old
    new = new if isinstance(new, dict) else new

    if not isinstance(old, dict) or not isinstance(new, dict):
        if old == new:
            return True, []
        if leaf_is_allowed(path) and isinstance(new, (str, int, float)):
            return True, []
        return False, [f"disallowed change at {'.'.join(path) or '<root>'}"]

    old_keys, new_keys = set(old.keys()), set(new.keys())
    added, removed = new_keys - old_keys, old_keys - new_keys
    reasons = []
    if added:
        reasons.append(f"new key(s) added at {'.'.join(path) or '<root>'}: {sorted(added)}")
    if removed:
        reasons.append(f"key(s) removed at {'.'.join(path) or '<root>'}: {sorted(removed)}")
    if reasons:
        return False, reasons

    ok, all_reasons = True, []
    for k in old_keys:
        sub_ok, sub_reasons = diff_dicts(old[k], new[k], path + (str(k),))
        if not sub_ok:
            ok = False
            all_reasons.extend(sub_reasons)
    return ok, all_reasons


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--base", required=True)
    p.add_argument("--files", nargs="+", required=True)
    args = p.parse_args()

    all_ok = True
    for path in args.files:
        old = load_ref_file(args.base, path)
        if old is None:
            print(f"{path}: not present on base ref -> treating as unsafe")
            all_ok = False
            continue
        new = load_file(path)
        ok, reasons = diff_dicts(old, new)
        if ok:
            print(f"{path}: OK (no changes, or tag/repository-only changes)")
        else:
            all_ok = False
            print(f"{path}: DISALLOWED changes:")
            for r in reasons:
                print(f"  - {r}")

    gh_output = os.environ.get("GITHUB_OUTPUT")
    if gh_output:
        with open(gh_output, "a") as f:
            f.write(f"safe={'true' if all_ok else 'false'}\n")

    print(f"\nResult: {'SAFE to auto-merge' if all_ok else 'NOT safe -- leaving for human review'}")


if __name__ == "__main__":
    main()
