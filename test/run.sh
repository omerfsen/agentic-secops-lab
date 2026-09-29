#!/bin/bash
# Runs every claim test against the lab. One sandbox, one helper namespace,
# torn down afterwards. Summary on stdout and in results.md next to this file.
set -u
cd "$(dirname "$0")"
. ./lib.sh
: > "$RESULTS_FILE"

echo "== preflight"
openshell status >/dev/null 2>&1 || { echo "openshell cannot reach the gateway (openshell status)"; exit 2; }
kubectl get nodes >/dev/null 2>&1 || { echo "kubectl cannot reach the cluster (KUBECONFIG=$KUBECONFIG)"; exit 2; }
echo "   gateway ok, cluster ok"

echo "== sandbox $SB from $SB_IMAGE"
sb_delete
sb_create || { echo "sandbox did not become Ready"; openshell sandbox list; exit 2; }
echo "   ready: $(openshell sandbox list | grep -E "^\s*$SB\s" | tr -s ' ')"

for t in ./t0*.sh; do
  echo; echo "== $t"
  bash "$t"
done

echo; echo "== teardown"
sb_delete
kubectl delete namespace "$NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
openshell provider delete claimtest-echo >/dev/null 2>&1 || true

echo; echo "== summary"
{
  echo "# Claim test results — $(date -u +%Y-%m-%dT%H:%MZ)"
  echo
  echo "Guest: $(hostname) · $(. /etc/os-release && echo "$PRETTY_NAME") · $(uname -r) · gateway $(openshell status 2>/dev/null | awk '/Version/{print $2}') · image $SB_IMAGE"
  echo
  echo "| result | test | claim | evidence |"
  echo "|---|---|---|---|"
  awk -F'|' '{printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4}' "$RESULTS_FILE"
} > results.md
awk -F'|' '{printf "%-4s %s — %s\n", $1, $2, $3}' "$RESULTS_FILE"
echo; echo "$(grep -c '^PASS' "$RESULTS_FILE") pass, $(grep -c '^FAIL' "$RESULTS_FILE") fail, $(grep -c '^SKIP' "$RESULTS_FILE") skip — written to $(pwd)/results.md"
