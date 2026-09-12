#!/usr/bin/env python3
"""Point azure-k3s.yaml at one of the three deployment shapes.

Usage: set-shape.py services|dev-bundle|domain-split

Sets the environment domain and repoints the egov-service-host keys for the
16 bundled services at the right upstream for the shape:
  services      per-service Services      (modulith.digit.org)
  dev-bundle    the single bundle Service (modulith-test.digit.org)
  domain-split  each service's bundle     (domain-split.digit.org)
Run cluster-configs sync + a rollout restart of consumers after switching.
"""
import re, sys, pathlib

DOMAINS = {"services": "modulith.digit.org",
           "dev-bundle": "modulith-test.digit.org",
           "domain-split": "domain-split.digit.org"}
BUNDLE_OF = {  # feat/modulith-domain-split bundles.package.yaml compositions
    "otp-java": "identity-bundle", "individual-java": "identity-bundle",
    "employee-java": "identity-bundle",
    "template-config-java": "notification-bundle", "notification-java": "notification-bundle",
    "billing-java": "billing-bundle", "apportion": "billing-bundle",
    "idgen-java": "admin-bundle", "localization-java": "admin-bundle",
    "workflow-java": "admin-bundle", "registry-java": "admin-bundle",
    "filestore-java": "admin-bundle", "boundary-java": "admin-bundle",
}

shape = sys.argv[1]
path = pathlib.Path(__file__).parent / "azure-k3s.yaml"
text = path.read_text()

for old in set(DOMAINS.values()) - {DOMAINS[shape]}:
    text = text.replace(old, DOMAINS[shape])

def upstream(key):
    if shape == "services":
        return f"http://{key}.egov.svc.cluster.local:8080/"
    if shape == "dev-bundle":
        return "http://dev-bundle.egov.svc.cluster.local:8080/"
    return f"http://{BUNDLE_OF[key]}.egov.svc.cluster.local:8080/"

for key in BUNDLE_OF:
    pat = rf'^(\s+{re.escape(key)}: )"http://[^"]+"( # modulith .*)?$'
    text = re.sub(pat, lambda m: f'{m.group(1)}"{upstream(key)}" # modulith shape-managed',
                  text, count=1, flags=re.M)

path.write_text(text)
print(f"shape={shape} domain={DOMAINS[shape]}")
for key in sorted(BUNDLE_OF):
    m = re.search(rf'^\s+{re.escape(key)}: "([^"]+)"', text, flags=re.M)
    print(f"  {key:22} -> {m.group(1)}")
