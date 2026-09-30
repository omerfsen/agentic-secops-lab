#!/bin/bash
# Claim 7: SUSE Security (NeuVector) watches the workloads — the sandbox pod
# must show up in NeuVector's own inventory. Talks to the controller's REST
# API (port 10443) directly. Credentials, first match wins:
#   NV_APIKEY="name:secret"   a NeuVector API key (Settings > API Keys, role reader)
#   NV_PASSWORD="…"           the admin password
#   the file $NV_CRED_FILE (default: .nv-credentials next to this script) with
#   NV_APIKEY=… and/or NV_PASSWORD=… lines — how run-from-host.sh passes them
# Nothing secret is printed, and secrets never go on a command line.
. "$(dirname "$0")/lib.sh"
ID=t07; CLAIM="NeuVector monitors the sandbox workload"
NV_CRED_FILE="${NV_CRED_FILE:-$(dirname "$0")/.nv-credentials}"
if [ -f "$NV_CRED_FILE" ]; then
  [ -z "${NV_APIKEY:-}" ]   && NV_APIKEY=$(sed -n 's/^NV_APIKEY=//p' "$NV_CRED_FILE" | head -1)
  [ -z "${NV_PASSWORD:-}" ] && NV_PASSWORD=$(sed -n 's/^NV_PASSWORD=//p' "$NV_CRED_FILE" | head -1)
fi

ctl=$(kubectl -n neuvector get pods -l app=neuvector-controller-pod --field-selector=status.phase=Running \
      -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)
[ -z "$ctl" ] && { skip $ID "$CLAIM" "no running NeuVector controller found"; exit 0; }
API="https://$ctl:10443/v1"
read -r pns pname < <(sb_pod)
[ -z "$pname" ] && { skip $ID "$CLAIM" "sandbox pod not found"; exit 0; }

tmp=$(umask 077; mktemp -d); trap 'rm -rf "$tmp"' EXIT
token=""
if [ -n "${NV_APIKEY:-}" ]; then
  printf 'X-Auth-Apikey: %s\n' "$NV_APIKEY" > "$tmp/hdr"; how="API key"
else
  [ -z "${NV_PASSWORD:-}" ] && { skip $ID "$CLAIM" "set NV_APIKEY (name:secret) or NV_PASSWORD to run this"; exit 0; }
  python3 -c 'import json,sys; print(json.dumps({"password":{"username":"admin","password":sys.stdin.read().rstrip("\n")}}))' \
    <<< "$NV_PASSWORD" > "$tmp/body"
  resp=$(curl -sk -m 15 -X POST "$API/auth" -H 'Content-Type: application/json' -d @"$tmp/body")
  echo "$resp" | grep -q '"need_to_reset_password": *true' && {
    skip $ID "$CLAIM" "admin password is still the bootstrap value; log in to the UI once to set it, or use an API key"; exit 0; }
  token=$(echo "$resp" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("token") or {}).get("token",""))' 2>/dev/null)
  [ -z "$token" ] && { skip $ID "$CLAIM" "controller rejected the admin password"; exit 0; }
  printf 'X-Auth-Token: %s\n' "$token" > "$tmp/hdr"; how="admin password"
fi

code=$(curl -sk -m 30 -o "$tmp/wl.json" -w '%{http_code}' "$API/workload" -H @"$tmp/hdr")
[ -n "$token" ] && curl -sk -m 10 -X DELETE "$API/auth" -H @"$tmp/hdr" >/dev/null 2>&1
[ "$code" != "200" ] && { fail $ID "$CLAIM" "controller API answered HTTP $code to GET /v1/workload with the $how"; exit 0; }

found=$(python3 - "$pname" "$tmp/wl.json" <<'PY'
import json, sys
pod, path = sys.argv[1], sys.argv[2]
ws = json.load(open(path)).get("workloads", [])
hits = [w for w in ws if pod in (w.get("pod_name", ""), w.get("display_name", "")) or pod in w.get("name", "")]
print(len(ws), len(hits))
for w in hits[:3]:
    print("  %s | domain=%s state=%s mode=%s service=%s" % (w.get("display_name") or w.get("name"),
          w.get("domain", "?"), w.get("state", "?"), w.get("policy_mode", "?"), w.get("service", "?")))
PY
)
read -r total hits <<< "$(echo "$found" | head -1)"
evidence "logged in to the controller API with the $how; NeuVector lists $total workloads, $hits match pod $pns/$pname"
echo "$found" | tail -n +2 | while read -r l; do [ -n "$l" ] && evidence "$l"; done

if [ "${hits:-0}" -ge 1 ]; then
  pass $ID "$CLAIM" "the sandbox pod is in NeuVector's workload inventory ($(echo "$found" | sed -n 2p | sed 's/^ *//' | cut -c1-120))"
else
  fail $ID "$CLAIM" "NeuVector lists $total workloads but not the sandbox pod $pname"
fi
