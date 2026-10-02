#!/usr/bin/env python3
"""Gate for the backbone chart values auto-merge workflow.

Companion to validate_tag_bump.py, kept separate on purpose: the two lanes
allow different files and take opposite approaches to what they permit.

The tag lane is an ALLOWLIST -- only image.tag/image.repository may change.
This lane is a DENYLIST: any key in the two allowlisted backbone chart
values files may change, EXCEPT paths that touch credentials, container
escape hatches, or the identity/privilege posture of the workload. Those
fall back to normal human/code-owner review.

The point is that ordinary tuning -- replicas, resources, nodeSelector,
tolerations, affinity, probes, service ports, ingress hosts, image tags,
chart config -- should be self-service, while the roughly dozen keys that
let a values change become arbitrary code execution, a cloud credential
rebind, or a database auth rewrite should not merge unreviewed.

A path is denied if:
  * any component matches a DENIED_KEYS entry (denies the whole subtree,
    at any nesting depth -- e.g. workers.extraVolumeMounts as well as
    scheduler.extraVolumeMounts), or
  * any component contains a DENIED_SUBSTRINGS fragment, case-insensitively
    (catches credential keys not enumerated by name), or
  * the path contains a DENIED_SEQUENCES run of consecutive components
    (for keys only sensitive in context, e.g. serviceAccount.annotations
    while leaving ingress/service annotations self-service).

Two value checks run on top of the path denylist, because some changes are
path-wise fine but not symmetrically revertable the way an image tag is:

  * resources cpu/memory must be valid Kubernetes quantities with
    requests <= limits -- an unparseable quantity or a memory limit below
    the working set takes the service down on the next reconcile
  * PVC sizes may grow but not shrink -- a volume cannot be shrunk in
    place, and on a StatefulSet the attempt wedges the reconcile

Exits 0 either way and writes safe=true|false to $GITHUB_OUTPUT; the
workflow decides what to do with that.
"""
import argparse
import os
import re
import subprocess

import yaml

# Whole-subtree denials. Matched against every component of a path, at any
# depth, because these keys recur per-component in the airflow chart
# (workers.*, scheduler.*, triggerer.*, webserver.*, dagProcessor.*).
DENIED_KEYS = frozenset({
    # --- Credentials and signing keys (airflow) -----------------------
    "fernetKey", "fernetKeySecretName",
    "webserverSecretKey", "webserverSecretKeySecretName",
    "defaultUser",
    # --- Arbitrary execution / container escape hatches --------------
    # extraContainers and extraInitContainers are a full pod spec;
    # extraVolumes/Mounts can mount a host path; command/args replace the
    # entrypoint; extraEnv* can inject credentials or alter behaviour.
    "extraEnv", "extraEnvFrom", "extraEnvsFrom",
    "extraContainers", "extraInitContainers",
    "extraVolumes", "extraVolumeMounts",
    "command", "args",
    "lifecycle", "extraPipPackages",
    # --- Host-level escape -------------------------------------------
    "hostNetwork", "hostPID", "hostIPC", "hostPath", "hostAliases",
    "privileged", "allowPrivilegeEscalation", "capabilities",
    # --- Identity and privilege posture ------------------------------
    "rbac", "securityContext", "securityContexts",
    "podSecurityContext", "containerSecurityContext",
    "runAsUser", "runAsGroup", "fsGroup",
    # --- Where the executed code comes from (airflow DAGs) -----------
    "gitSync",
    # --- Auth surface (clickhouse) -----------------------------------
    "extraUsersConfig",
    "imagePullSecrets",
    "useExistingConfigSecret", "existingConfigSecret",
})

# Substring denials, case-insensitive, matched against each component.
# Enumerating credential keys by name is a losing game across two charts
# of ~3600 lines combined, so anything that reads like a credential is
# routed to review even if it is not listed above.
DENIED_SUBSTRINGS = ("secret", "password", "passwd", "token", "credential", "apikey", "privatekey")

# Denials that only apply in context, so the bare key stays self-service.
DENIED_SEQUENCES = (
    # Workload-identity / IRSA binding -> cloud credential escalation.
    # Ingress and service annotations are deliberately NOT denied.
    ("serviceAccount", "annotations"),
    # Redundant with the gitSync subtree denial, kept explicit so the
    # intent survives someone pruning DENIED_KEYS.
    ("dags", "gitSync"),
)

# Resource paths still get a value check. Anchored on three components so
# resources.requests.storage is excluded -- clickhouse keeps PVC storage
# under a resources.requests parent right next to cpu/memory, and storage
# is handled by the shrink guard below instead.
RESOURCE_LEAF_SUFFIXES = (
    ("resources", "limits", "cpu"),
    ("resources", "limits", "memory"),
    ("resources", "requests", "cpu"),
    ("resources", "requests", "memory"),
)

# Volume size leaves. Growing a PVC is a normal, self-service operation on
# a storage class with allowVolumeExpansion; shrinking one is not possible
# in place, and on a StatefulSet it wedges the reconcile. So these stay
# self-service in the growth direction only.
VOLUME_SIZE_KEYS = frozenset({"storage", "size"})

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


def denial_reason(path_tuple):
    """Return why this path is denied, or None if it is self-service."""
    for component in path_tuple:
        if component in DENIED_KEYS:
            return f"{component!r} is a protected key (credential, execution or privilege surface)"
        lowered = component.lower()
        for fragment in DENIED_SUBSTRINGS:
            if fragment in lowered:
                return f"{component!r} looks like a credential ({fragment!r})"
    for sequence in DENIED_SEQUENCES:
        window = len(sequence)
        for i in range(len(path_tuple) - window + 1):
            if tuple(path_tuple[i:i + window]) == sequence:
                return f"{'.'.join(sequence)!r} is protected in this context"
    return None


def scan_subtree(node, path):
    """Find denied paths anywhere inside a changed list or scalar subtree.

    Lists cannot be diffed positionally in a way that stays meaningful, so
    a changed list is treated as one change at its own path. That would
    miss a denied key nested inside the new value, hence this scan.
    """
    reasons = []
    reason = denial_reason(path)
    if reason:
        reasons.append(f"disallowed change at {'.'.join(path) or '<root>'}: {reason}")
        return reasons
    if isinstance(node, dict):
        for key, value in node.items():
            reasons.extend(scan_subtree(value, path + (str(key),)))
    elif isinstance(node, list):
        for item in node:
            reasons.extend(scan_subtree(item, path))
    return reasons


def collect_resource_leaves(node, path):
    """Paths of resource cpu/memory leaves inside a changed subtree."""
    leaves = []
    if any(
        len(path) >= len(suffix) and tuple(path[-len(suffix):]) == suffix
        for suffix in RESOURCE_LEAF_SUFFIXES
    ):
        leaves.append(path)
    if isinstance(node, dict):
        for key, value in node.items():
            leaves.extend(collect_resource_leaves(value, path + (str(key),)))
    return leaves


def diff_docs(old, new, path=()):
    """Walk both docs in step.

    Returns (reasons, changed_paths). Empty reasons means every difference
    landed on a self-service path. changed_paths lists the subtree roots
    that differ, so the caller can value-check touched resources.
    """
    if isinstance(old, dict) and isinstance(new, dict):
        reasons, changed = [], []
        for key in sorted(set(old) | set(new), key=str):
            sub_path = path + (str(key),)
            if key not in old:
                # Adding a key is fine unless the key itself is protected.
                reasons.extend(scan_subtree(new[key], sub_path))
                changed.append(sub_path)
            elif key not in new:
                reason = denial_reason(sub_path)
                if reason:
                    reasons.append(
                        f"disallowed removal at {'.'.join(sub_path)}: {reason}"
                    )
                changed.append(sub_path)
            else:
                sub_reasons, sub_changed = diff_docs(old[key], new[key], sub_path)
                reasons.extend(sub_reasons)
                changed.extend(sub_changed)
        return reasons, changed

    if old == new:
        return [], []

    # Scalar or list changed: allowed unless this path -- or anything
    # inside the new value -- is protected.
    return scan_subtree(new, path), [path]


def get_at(doc, path):
    node = doc
    for key in path:
        if not isinstance(node, dict) or key not in node:
            return None
        node = node[key]
    return node


def check_volume_sizes(old, new, changed):
    """Deny PVC size decreases; allow growth."""
    reasons = []
    for path in changed:
        if not path or path[-1] not in VOLUME_SIZE_KEYS:
            continue
        before, after = parse_memory(get_at(old, path)), parse_memory(get_at(new, path))
        if before is None or after is None:
            continue
        if after < before:
            reasons.append(
                f"{'.'.join(path)} shrinks {get_at(old, path)!r} -> {get_at(new, path)!r} "
                "-- a PVC cannot be shrunk in place and this wedges the reconcile"
            )
    return reasons


def check_resource_block(doc, block_path, max_cpu, max_memory):
    """Validate quantities and requests <= limits within one block."""
    block = get_at(doc, block_path)
    where = ".".join(block_path) or "<root>"
    if not isinstance(block, dict):
        return []

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
        reasons, changed = diff_docs(old, new)

        if not reasons:
            blocks = set()
            for sub_path in changed:
                for leaf in collect_resource_leaves(get_at(new, sub_path), sub_path):
                    blocks.add(leaf[:-2])
            for block in sorted(blocks):
                reasons.extend(check_resource_block(new, block, args.max_cpu, max_memory))
            reasons.extend(check_volume_sizes(old, new, changed))

        if reasons:
            all_ok = False
            print(f"{path}: DISALLOWED changes:")
            for r in reasons:
                print(f"  - {r}")
        else:
            total_changed += len(changed)
            if changed:
                print(f"{path}: OK ({len(changed)} path(s) changed)")
                for sub_path in sorted(changed):
                    print(f"    {'.'.join(sub_path)} -> {get_at(new, sub_path)!r}")
            else:
                print(f"{path}: OK (no changes)")

    if all_ok and total_changed == 0:
        print("\nNo values changed -- nothing for this lane to do.")
        all_ok = False

    gh_output = os.environ.get("GITHUB_OUTPUT")
    if gh_output:
        with open(gh_output, "a") as f:
            f.write(f"safe={'true' if all_ok else 'false'}\n")

    print(f"\nResult: {'SAFE to auto-merge' if all_ok else 'NOT safe -- leaving for human review'}")


if __name__ == "__main__":
    main()
