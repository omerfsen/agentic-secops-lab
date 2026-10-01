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
ID=t07; CLAIM="NeuVector monitors the sandbox at runtime (sees the processes it runs)"
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

uid=$(kubectl -n "$pns" get pod "$pname" -o jsonpath='{.metadata.uid}')
code=$(curl -sk -m 30 -o "$tmp/wl.json" -w '%{http_code}' "$API/workload" -H @"$tmp/hdr")
[ "$code" != "200" ] && { [ -n "$token" ] && curl -sk -m 10 -X DELETE "$API/auth" -H @"$tmp/hdr" >/dev/null 2>&1
  fail $ID "$CLAIM" "controller API answered HTTP $code to GET /v1/workload with the $how"; exit 0; }
# the RUNNING agent container of THIS pod: exact pod name, namespace and UID; no pause, init or exited entries
agent=$(python3 - "$pname" "$pns" "$uid" "$tmp/wl.json" <<'PYX'
import json, sys
pod, ns, uid, path = sys.argv[1:]
ws = json.load(open(path)).get("workloads", [])
a = [w for w in ws if w.get("pod_name") == pod and w.get("domain") == ns and w.get("running")
     and w.get("name", "").startswith("k8s_agent_%s_%s_%s_" % (pod, ns, uid))]
print(a[0]["id"] if a else "", a[0].get("state", "?") if a else "", a[0].get("policy_mode", "?") if a else "", len(ws))
PYX
)
read -r aid astate amode total <<< "$agent"
evidence "logged in to the controller API with the $how; $total workloads listed; running agent container of $pns/$pname: ${aid:-NOT FOUND} (state=${astate:-?}, mode=${amode:-?})"
if [ -z "$aid" ]; then
  [ -n "$token" ] && curl -sk -m 10 -X DELETE "$API/auth" -H @"$tmp/hdr" >/dev/null 2>&1
  fail $ID "$CLAIM" "NeuVector does not list a running agent container for $pns/$pname"; exit 0
fi
# behavioural monitoring: a uniquely named real binary run inside the sandbox must show up in NeuVector's process history
mark="nvmark$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
sb_exec "cp \$(readlink -f /usr/bin/curl) /tmp/$mark && /tmp/$mark --version >/dev/null; rm -f /tmp/$mark" >/dev/null
seen() { curl -sk -m 15 "$API/workload/$aid/process_history" -H @"$tmp/hdr" | grep -q "\"$mark\""; }
t0=$(date +%s); if wait_until 60 seen; then sec=$(( $(date +%s) - t0 )); else sec=""; fi
scan=$(curl -sk -m 15 "$API/scan/config" -H @"$tmp/hdr" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("config", d).get("auto_scan"))' 2>/dev/null)
[ -n "$token" ] && curl -sk -m 10 -X DELETE "$API/auth" -H @"$tmp/hdr" >/dev/null 2>&1
if [ -n "$sec" ]; then evidence "process $mark started in the sandbox: recorded by NeuVector within ${sec}s"; else evidence "process $mark started in the sandbox: NOT recorded within 60s"; fi
evidence "vulnerability auto-scan: ${scan:-unknown}; image and container CVE scanning is not exercised by this test"
if [ -n "$sec" ]; then
  pass $ID "$CLAIM" "NeuVector tracks the running sandbox container and recorded a process started inside it within ${sec}s"
else
  fail $ID "$CLAIM" "NeuVector lists the container but did not record a process started inside it"
fi
