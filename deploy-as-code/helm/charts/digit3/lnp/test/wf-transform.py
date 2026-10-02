"""test-lts workflow definition export (ids in actions) -> modulith workflow POST body (codes, flat)."""
import json,sys
d=json.load(open(sys.argv[1])); byid={s["id"]:s["code"] for s in d["states"]}
out={k:d[k] for k in ("code","name","description","version","sla") if k in d}
out["states"]=[{**{k:s[k] for k in ("code","name","type","description","sla") if k in s},
                "actions":[{"code":a["code"],"label":a.get("label"),"nextState":byid.get(a["nextState"],a["nextState"]),"roles":a.get("roles") or []} for a in (s.get("actions") or [])]}
               for s in d["states"]]
print(json.dumps(out))
