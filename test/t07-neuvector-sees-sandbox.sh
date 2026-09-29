#!/bin/bash
# Claim 7: SUSE Security (NeuVector) runtime-scans the workloads — the
# sandbox pod must show up as a monitored workload. Uses NV_PASSWORD, or the
# chart's bootstrap admin password if that has not been changed yet.
. "$(dirname "$0")/lib.sh"
ID=t07; CLAIM="NeuVector monitors the sandbox workload"
ing=$(kubectl -n neuvector get ingress -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null)
NV_URL="${NV_URL:-https://${ing:-neuvector.$(hostname -I | awk '{print $1}').sslip.io}}"
src="NV_PASSWORD"
if [ -z "${NV_PASSWORD:-}" ]; then
  NV_PASSWORD=$(kubectl -n neuvector get secret neuvector-bootstrap-secret -o go-template='{{ .data.bootstrapPassword | base64decode }}' 2>/dev/null)
  src="bootstrap secret"
fi
[ -z "${NV_PASSWORD:-}" ] && { skip $ID "$CLAIM" "set NV_PASSWORD (NeuVector admin) to run this"; exit 0; }
read -r pns pname < <(sb_pod)
[ -z "$pname" ] && { skip $ID "$CLAIM" "sandbox pod not found"; exit 0; }

body=$(python3 -c 'import json,os,sys; print(json.dumps({"username":"admin","password":sys.argv[1],"isRancherSSOUrl":False}))' "$NV_PASSWORD")
token=$(curl -sk -m 15 -X POST "$NV_URL/auth" -H 'Content-Type: application/json' -d "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",{}).get("token",""))' 2>/dev/null)
[ -z "$token" ] && { skip $ID "$CLAIM" "could not log in to NeuVector at $NV_URL with the $src; set NV_PASSWORD"; exit 0; }
evidence "logged in to $NV_URL with the $src"

wl=$(curl -sk -m 20 "$NV_URL/workload" -H "X-Auth-Token: $token" | python3 -c '
import json,sys; n=sys.argv[1]
ws=[w for w in json.load(sys.stdin).get("workloads",[]) if n in w.get("name","") or n in w.get("display_name","")]
print(len(ws), (ws[0].get("state","?")+" mode="+ws[0].get("policy_mode","?")) if ws else "")' "$pname" 2>/dev/null)
curl -sk -m 10 -X DELETE "$NV_URL/auth" -H "X-Auth-Token: $token" >/dev/null 2>&1
evidence "workloads matching $pname: $wl"
if [ "${wl%% *}" != "0" ] && [ -n "$wl" ]; then
  pass $ID "$CLAIM" "NeuVector lists the sandbox pod ($wl)"
else
  fail $ID "$CLAIM" "NeuVector does not list $pname"
fi
