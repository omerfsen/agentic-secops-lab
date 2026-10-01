#!/bin/bash
# Claim 5: real credentials are injected at the network boundary; raw tokens
# never sit inside the agent environment. A provider holds a random fake
# secret; an in-cluster echo service stands in for the provider's API and logs
# what it receives, without sending it back into the sandbox. What the sandbox
# holds is checked from inside (with a pattern that never contains the secret)
# and from the node (every process and the container's files).
. "$(dirname "$0")/lib.sh"
ID=t05; CLAIM="credentials injected at the network boundary, never inside the sandbox"
SECRET="sk-claimtest-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"   # 16 hex digits
RX='sk-claimtest-[0-9a-f]{16}'
PROV="claimtest-echo"
ECHO_HOST="echo.$NS.svc.cluster.local"
CRED_SB="$SB-cred"
cleanup() { openshell sandbox delete "$CRED_SB" >/dev/null 2>&1; openshell provider delete "$PROV" >/dev/null 2>&1; openshell provider profile delete "$PROV" >/dev/null 2>&1; }

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$NS" apply -f - >/dev/null <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: {name: echo}
spec:
  replicas: 1
  selector: {matchLabels: {app: echo}}
  template:
    metadata: {labels: {app: echo}}
    spec:
      containers:
        - name: echo
          image: docker.io/mendhak/http-https-echo:37
          env: [{name: ECHO_BACK_TO_CLIENT, value: "false"}]
          ports: [{containerPort: 8080}]
---
apiVersion: v1
kind: Service
metadata: {name: echo}
spec:
  selector: {app: echo}
  ports: [{port: 8080, targetPort: 8080}]
YAML
kubectl -n "$NS" rollout status deployment/echo --timeout=180s >/dev/null 2>&1 || { skip $ID "$CLAIM" "echo service did not come up"; exit 0; }

cleanup
out=$(openshell provider profile import -f "$(dirname "$0")/claimtest-echo.profile.yaml" 2>&1) \
  && out=$(ECHO_API_KEY="$SECRET" openshell provider create --name "$PROV" --type "$PROV" --credential ECHO_API_KEY 2>&1)   # value from the environment, not argv
openshell provider list 2>/dev/null | grep -q "$PROV" || { cleanup; skip $ID "$CLAIM" "profile import / provider create failed: $(echo "$out" | tr '\n' ' ' | cut -c1-200)"; exit 0; }
openshell sandbox create --name "$CRED_SB" --from "$SB_IMAGE" --no-tty --detach --provider "$PROV" -- sleep 1800 >/dev/null 2>&1
SB_SAVE=$SB; SB="$CRED_SB"
{ sb_wait_ready 240 && sb_exec_ready 120; } || { SB=$SB_SAVE; cleanup; skip $ID "$CLAIM" "sandbox with provider never became Ready"; exit 0; }

look() {
  sb_exec "printf 'placeholder %s\n' \"\$(printf %s \"\$ECHO_API_KEY\" | cut -c1-22)\"
printf 'env %s\n' \"\$(env | grep -cE '$RX')\"
printf 'files %s\n' \"\$(grep -rlE '$RX' /sandbox /tmp /etc /var/log 2>/dev/null | head -3 | tr '\n' ' ')\"
echo DONE"
}
host_scan() {
  local cri="sudo /var/lib/rancher/rke2/bin/crictl --runtime-endpoint unix:///run/k3s/containerd/containerd.sock"
  local cid pid ns pat p hits=""
  cid=$($cri ps -q --name agent --label "io.kubernetes.pod.name=default--$CRED_SB" 2>/dev/null | head -1)
  pid=$($cri inspect "$cid" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["info"]["pid"])' 2>/dev/null)
  [ -z "$pid" ] && { echo "ERROR no container pid"; return; }
  ns=$(sudo readlink /proc/$pid/ns/pid)
  pat=$(umask 077; mktemp); printf '%s\n' "$SECRET" > "$pat"
  for p in $(sudo sh -c "for d in /proc/[0-9]*; do [ \"\$(readlink \$d/ns/pid)\" = '$ns' ] && echo \${d#/proc/}; done"); do
    sudo grep -qaFf "$pat" /proc/$p/environ /proc/$p/cmdline 2>/dev/null && hits="$hits pid$p"
  done
  sudo grep -rlaFf "$pat" /proc/$pid/root/sandbox /proc/$pid/root/tmp /proc/$pid/root/etc /proc/$pid/root/run /proc/$pid/root/var 2>/dev/null \
    | head -3 | sed 's|^/proc/[0-9]*/root|file:|'
  rm -f "$pat"; echo "procs:${hits:- none}"
}
clean()  { [ "$(kv "$1" env)" = "0" ] && [ -z "$(kv "$1" files | tr -d ' ')" ]; }
hclean() { echo "$1" | grep -q '^procs: none$' && ! echo "$1" | grep -qE '^(file:|ERROR)'; }

before=$(look); hb=$(host_scan)
code=$(sb_exec "curl -sS -m 20 -o /dev/null -w '%{http_code}' http://$ECHO_HOST:8080/v1/models -H \"Authorization: Bearer \$ECHO_API_KEY\"" | tail -1)
sleep 2
upstream=$(kubectl -n "$NS" logs deploy/echo --since=5m 2>/dev/null | grep -cF "Bearer $SECRET")
after=$(look); ha=$(host_scan)
SB=$SB_SAVE; cleanup

for v in "$before" "$after"; do echo "$v" | grep -q '^DONE$' || { fail $ID "$CLAIM" "an in-sandbox probe did not complete"; exit 0; }; done
ph=$(kv "$before" placeholder)
evidence "ECHO_API_KEY inside the sandbox: '$ph…'"
evidence "before the call: env matches $(kv "$before" env), file matches '$(kv "$before" files)', node-side scan: $(echo $hb)"
evidence "call from the sandbox: HTTP $code; the echo service's own log shows the real bearer token $upstream time(s)"
evidence "after the call: env matches $(kv "$after" env), file matches '$(kv "$after" files)', node-side scan: $(echo $ha)"

if ! echo "$ph" | grep -q '^openshell:resolve:env'; then
  fail $ID "$CLAIM" "ECHO_API_KEY in the sandbox is not an OpenShell placeholder"
elif ! clean "$before" || ! clean "$after" || ! hclean "$hb" || ! hclean "$ha"; then
  fail $ID "$CLAIM" "the real secret was found inside the sandbox (see evidence)"
elif [ "${upstream:-0}" -ge 1 ]; then
  pass $ID "$CLAIM" "the agent holds only a placeholder before and after the call; the upstream received the real token; node-side scans of the container found nothing"
else
  fail $ID "$CLAIM" "the secret never reached the sandbox, but the upstream did not receive it either (HTTP $code)"
fi
