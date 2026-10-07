#!/usr/bin/env python3
"""summarize.py <k6-summary.json> [vus] — one line per endpoint from a k6 --summary-export file, with the averages and the
Little's-law check: with N users and no think time, avg lifecycle must equal N / lifecycles-per-second."""
import json, sys
d = json.load(open(sys.argv[1])); m = d["metrics"]; vus = int(sys.argv[2]) if len(sys.argv) > 2 else None
g = lambda k, f: (m.get(k) or {}).get(f)
rate = g("lifecycles", "rate") or 0
print(f"iterations={g('iterations','count')}  lifecycles/s={rate:.2f}  req/s={g('http_reqs','rate') or 0:.1f}  errors={(g('http_req_failed','value') or 0)*100:.2f}%")
for n in ("apply", "verify", "search", "transition"):
    k = f"http_req_duration{{name:{n}}}"
    if k in m: print(f"  {n:11} avg={g(k,'avg'):7.0f}ms  p50={g(k,'p(50)'):7.0f}ms  p95={g(k,'p(95)'):7.0f}ms  p99={g(k,'p(99)'):7.0f}ms  max={g(k,'max'):7.0f}ms")
avg = g("lifecycle_duration", "avg") or 0
line = f"  lifecycle   avg={avg:7.0f}ms  p50={g('lifecycle_duration','p(50)') or 0:7.0f}ms  p95={g('lifecycle_duration','p(95)') or 0:7.0f}ms"
if vus and rate: line += f"   Little: N/rate={vus/rate*1000:6.0f}ms  measured avg={avg:6.0f}ms  ({(avg/(vus/rate*1000)-1)*100:+.0f}%)"
print(line)
