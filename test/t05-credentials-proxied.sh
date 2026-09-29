#!/bin/bash
# Claim 5: real credentials are injected at the network boundary; raw tokens
# never sit inside the agent environment. An in-cluster echo service stands
# in for the provider's API and returns the headers it received.
. "$(dirname "$0")/lib.sh"
ID=t05; CLAIM="credentials injected at the boundary, never inside the sandbox"
SECRET="sk-claimtest-$(date +%s)-NEVER-IN-SANDBOX"
PROV="claimtest-echo"
ECHO_HOST="echo.$NS.svc.cluster.local"
CRED_SB="$SB-cred"
cleanup() { openshell sandbox delete "$CRED_SB" >/dev/null 2>&1; openshell provider delete "$PROV" >/dev/null 2>&1; openshell provider profile delete "$PROV" >/dev/null 2>&1; }

# echo service: returns the request (headers included) as JSON
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$NS" apply -f - >/dev/null <<EOF
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
          ports: [{containerPort: 8080}]
---
apiVersion: v1
kind: Service
metadata: {name: echo}
spec:
  selector: {app: echo}
  ports: [{port: 8080, targetPort: 8080}]
EOF
kubectl -n "$NS" rollout status deployment/echo --timeout=180s >/dev/null 2>&1 || { skip $ID "$CLAIM" "echo service did not come up"; exit 0; }

# profile (which host may receive the credential, from which binaries) + provider (the secret itself)
cleanup
out=$(openshell provider profile import -f "$(dirname "$0")/claimtest-echo.profile.yaml" 2>&1) \
  && out=$(openshell provider create --name "$PROV" --type "$PROV" --credential "ECHO_API_KEY=$SECRET" 2>&1)
openshell provider list 2>/dev/null | grep -q "$PROV" || { cleanup; skip $ID "$CLAIM" "profile import / provider create failed: $(echo "$out" | tr '\n' ' ' | cut -c1-200)"; exit 0; }

openshell sandbox create --name "$CRED_SB" --from "$SB_IMAGE" --no-tty --detach --provider "$PROV" -- sleep 1800 >/dev/null 2>&1
SB_SAVE=$SB; SB="$CRED_SB"
{ sb_wait_ready 240 && sb_exec_ready 120; } || { SB=$SB_SAVE; cleanup; skip $ID "$CLAIM" "sandbox with provider never became Ready"; exit 0; }

inside_env=$(sb_exec 'printf %s "${ECHO_API_KEY-<unset>}"' | tail -1)
leak_env=$(sb_exec "env | grep -c -- '$SECRET'" | tail -1)
leak_fs=$(sb_exec "grep -rl -- '$SECRET' /sandbox /tmp /etc /root /home /run 2>/dev/null | head -3 | tr '\n' ' '")
evidence "ECHO_API_KEY inside the sandbox: '$(echo "$inside_env" | cut -c1-40)'; real secret in env: $leak_env; in files: ${leak_fs:-none}"

resp=$(sb_exec "curl -sS -m 20 http://$ECHO_HOST:8080/v1/models -H \"Authorization: Bearer \${ECHO_API_KEY:-none}\"")
auth_seen=$(echo "$resp" | grep -oE '"authorization": *"[^"]*"' | head -1)
evidence "echo service received: ${auth_seen:-no authorization header} $(echo "$resp" | grep -qE '"authorization"' || echo "(raw: $(echo "$resp" | tr '\n' ' ' | cut -c1-160))")"

SB=$SB_SAVE; cleanup

if [ "${leak_env:-1}" = "0" ] && [ -z "$leak_fs" ] && echo "$auth_seen" | grep -q -- "$SECRET"; then
  pass $ID "$CLAIM" "sandbox saw '$(echo "$inside_env" | cut -c1-24)…', the upstream saw the real secret"
elif [ "${leak_env:-1}" = "0" ] && [ -z "$leak_fs" ]; then
  fail $ID "$CLAIM" "secret never inside the sandbox (good) but the upstream did not receive it either: ${auth_seen:-none}"
else
  fail $ID "$CLAIM" "raw secret found inside the sandbox (env=$leak_env files=$leak_fs)"
fi
