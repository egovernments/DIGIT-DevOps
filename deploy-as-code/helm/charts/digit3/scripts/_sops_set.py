#!/usr/bin/env python3
"""sops EDITOR helper for lib.sh's sops_set(): sets SOPS_SET_PATH (dotted) to
SOPS_SET_VALUE in the decrypted temp file sops passes as argv[1]. The value
travels via the environment — never argv, never a file, never stdout."""
import os
import sys

import yaml

path = os.environ["SOPS_SET_PATH"].split(".")
value = os.environ["SOPS_SET_VALUE"]
tmp = sys.argv[1]

with open(tmp) as f:
    doc = yaml.safe_load(f) or {}

node = doc
for key in path[:-1]:
    node = node.setdefault(key, {})
node[path[-1]] = value

with open(tmp, "w") as f:
    yaml.safe_dump(doc, f, default_flow_style=False, sort_keys=False)
