#!/usr/bin/env python3
"""Gate for the resource-bump auto-merge workflow.

Companion to validate_tag_bump.py, kept separate on purpose: the two lanes
allow different files, different leaf paths, and this one applies value
checks that the tag lane has no use for.

Compares each given chart values file between the PR base and the PR head
and requires that the only differences are scalar values at a path ending
in resources.{limits,requests}.{cpu,memory} (at any nesting depth) for
keys that already existed on the base. Any added/removed key, or a change
anywhere else, marks the PR unsafe to auto-merge and leaves it for normal
human/code-owner review.

Unlike an image tag, a resource value is not symmetrically revertable: an
unparseable quantity, or a memory limit below the service's working set,
takes the service down on the next reconcile rather than just deploying
the wrong build. So a path match alone is not enough. For every resources
block the diff touched, this script also requires:

  * each changed cpu/memory value to be a valid Kubernetes quantity
  * requests <= limits, per resource, within that block
  * optionally, values at or below --max-cpu / --max-memory, to catch a
    request no node in the cluster can satisfy (pod stuck Pending)

Exits 0 either way and writes safe=true|false to $GITHUB_OUTPUT; the
workflow decides what to do with that.
"""
import argparse
import os
import re
import subprocess

import yaml

# Anchored on three components, not two, and deliberately excluding
# resources.requests.storage: both airflow and clickhouse keep PVC storage
# under a resources.requests parent right next to cpu/memory (e.g.
# clickhouse.cluster.spec.dataVolumeClaimSpec.resources.requests.storage).
# A PVC request cannot be shrunk in place, so letting it through this lane
# could wedge a StatefulSet reconcile. A two-component ("limits", "cpu")
# match would also collide with airflow's unrelated top-level `limits: []`.
ALLOWED_LEAF_SUFFIXES = (
    ("resources", "limits", "cpu"),
    ("resources", "limits", "memory"),
    ("resources", "requests", "cpu"),
    ("resources", "requests", "memory"),
)

# Kubernetes quantity formats: CPU is cores ("1", "0.5") or millicores
# ("500m"); memory is bytes with an optional decimal (k, M, G) or binary
# (Ki, Mi, Gi) suffix.
CPU_RE = re.compile(r"^(\d+(?:\.\d+)?)(m?)$")
MEM_RE = re.compile(r"^(\d+(?:\.\d+)?)(|k|M|G|T|P|E|Ki|Mi|Gi|Ti|Pi|Ei)$")
MEM_MULTIPLIERS = {
    "": 1,
    "k": 10**3, "M": 10**6, "G": 10**9,
    "T": 10**12, "P": 10**15, "E": 10**18,
    "Ki": 2**10, "Mi": 2**20, "Gi": 2**30,
    "Ti": 2**40, "Pi": 2**50, "Ei": 2**60,
}


def parse_cpu(value):
    """Return millicores as a float, or None if not a valid CPU quantity."""
    m = CPU_RE.match(str(value).strip())
    if not m:
        return None
    number, suffix = float(m.group(1)), m.group(2)
    return number if suffix == "m" else number * 1000


def parse_memory(value):
    """Return bytes as a float, or None if not a valid memory quantity."""
    m = MEM_RE.match(str(value).strip())
    if not m:
        return None
    return float(m.group(1)) * MEM_MULTIPLIERS[m.group(2)]


PARSERS = {"cpu": parse_cpu, "memory": parse_memory}
DISPLAY_UNIT = {"cpu": "millicores", "memory": "bytes"}


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
    return any(
        len(path_tuple) >= len(suffix) and path_tuple[-len(suffix):] == suffix
        for suffix in ALLOWED_LEAF_SUFFIXES
    )


def diff_dicts(old, new, path=()):
    """Walk both docs in step.

    Returns (ok, reasons, changed_paths) where changed_paths lists the
    allowlisted leaves that actually differ, so the caller can value-check
    just the blocks this PR touched instead of the whole file.
    """
    if not isinstance(old, dict) or not isinstance(new, dict):
        if old == new:
            return True, [], []
        if leaf_is_allowed(path) and isinstance(new, (str, int, float)):
            return True, [], [path]
        return False, [f"disallowed change at {'.'.join(path) or '<root>'}"], []

    old_keys, new_keys = set(old.keys()), set(new.keys())
    added, removed = new_keys - old_keys, old_keys - new_keys
    reasons = []
    if added:
        reasons.append(f"new key(s) added at {'.'.join(path) or '<root>'}: {sorted(added)}")
    if removed:
        reasons.append(f"key(s) removed at {'.'.join(path) or '<root>'}: {sorted(removed)}")
    if reasons:
        return False, reasons, []

    ok, all_reasons, all_changed = True, [], []
    for k in old_keys:
        sub_ok, sub_reasons, sub_changed = diff_dicts(old[k], new[k], path + (str(k),))
        if not sub_ok:
            ok = False
            all_reasons.extend(sub_reasons)
        all_changed.extend(sub_changed)
    return ok, all_reasons, all_changed


def touched_resource_blocks(changed_paths):
    """Map changed leaves back to their nearest enclosing resources block."""
    blocks = set()
    for leaf in changed_paths:
        # Every allowlisted leaf ends in resources.<section>.<resource>, so
        # the block is always the third-from-last component.
        blocks.add(leaf[:-2])
    return sorted(blocks)


def get_at(doc, path):
    node = doc
    for key in path:
        if not isinstance(node, dict) or key not in node:
            return None
        node = node[key]
    return node


def check_resource_block(doc, block_path, max_cpu, max_memory):
    """Validate quantities and requests <= limits within one block."""
    block = get_at(doc, block_path)
    where = ".".join(block_path) or "<root>"
    if not isinstance(block, dict):
        return [f"expected a mapping at {where}"]

    reasons, parsed = [], {}
    for section in ("requests", "limits"):
        values = block.get(section)
        if not isinstance(values, dict):
            continue
        for resource, parse in PARSERS.items():
            if resource not in values:
                continue
            raw = values[resource]
            quantity = parse(raw)
            if quantity is None:
                reasons.append(
                    f"not a valid {resource} quantity at {where}.{section}.{resource}: {raw!r}"
                )
                continue
            if quantity <= 0:
                reasons.append(f"{where}.{section}.{resource} must be > 0, got {raw!r}")
                continue
            parsed[(section, resource)] = (quantity, raw)

    for resource in PARSERS:
        request = parsed.get(("requests", resource))
        limit = parsed.get(("limits", resource))
        if request and limit and request[0] > limit[0]:
            reasons.append(
                f"requests.{resource} ({request[1]!r}) exceeds limits.{resource} "
                f"({limit[1]!r}) at {where} -- Kubernetes rejects this spec"
            )

    ceilings = {"cpu": max_cpu, "memory": max_memory}
    for (section, resource), (quantity, raw) in sorted(parsed.items()):
        ceiling = ceilings[resource]
        if ceiling is not None and quantity > ceiling:
            reasons.append(
                f"{where}.{section}.{resource} ({raw!r}) is above the configured "
                f"ceiling of {ceiling:g} {DISPLAY_UNIT[resource]} -- likely unschedulable"
            )

    return reasons


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--base", required=True, help="PR base ref to diff against")
    p.add_argument("--files", nargs="+", required=True)
    p.add_argument(
        "--max-cpu",
        type=float,
        default=None,
        help="Optional ceiling for any single cpu value, in millicores (e.g. 8000).",
    )
    p.add_argument(
        "--max-memory",
        type=str,
        default=None,
        help="Optional ceiling for any single memory value, as a quantity (e.g. 16Gi).",
    )
    args = p.parse_args()

    max_memory = None
    if args.max_memory is not None:
        max_memory = parse_memory(args.max_memory)
        if max_memory is None:
            p.error(f"--max-memory is not a valid quantity: {args.max_memory!r}")

    all_ok = True
    total_changed = 0
    for path in args.files:
        old = load_ref_file(args.base, path)
        if old is None:
            print(f"{path}: not present on base ref -> treating as unsafe")
            all_ok = False
            continue

        new = load_file(path)
        ok, reasons, changed = diff_dicts(old, new)

        if ok:
            for block in touched_resource_blocks(changed):
                reasons.extend(check_resource_block(new, block, args.max_cpu, max_memory))
            ok = not reasons

        if ok:
            total_changed += len(changed)
            if changed:
                print(f"{path}: OK ({len(changed)} resource value(s) changed)")
                for leaf in sorted(changed):
                    print(f"    {'.'.join(leaf)} -> {get_at(new, leaf)!r}")
            else:
                print(f"{path}: OK (no changes)")
        else:
            all_ok = False
            print(f"{path}: DISALLOWED changes:")
            for r in reasons:
                print(f"  - {r}")

    if all_ok and total_changed == 0:
        print("\nNo resource values changed -- nothing for this lane to do.")
        all_ok = False

    gh_output = os.environ.get("GITHUB_OUTPUT")
    if gh_output:
        with open(gh_output, "a") as f:
            f.write(f"safe={'true' if all_ok else 'false'}\n")

    print(f"\nResult: {'SAFE to auto-merge' if all_ok else 'NOT safe -- leaving for human review'}")


if __name__ == "__main__":
    main()
