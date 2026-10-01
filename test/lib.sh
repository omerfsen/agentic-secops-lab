#!/bin/bash
# Shared helpers for the claim tests. Sourced, not executed.

export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

SB="${SB:-claimtest}"                               # sandbox name
SB_IMAGE="${SB_IMAGE:-docker.io/nicolaka/netshoot:latest}"
NS="${NS:-claimtest}"                               # namespace for helpers
RESULTS_FILE="${RESULTS_FILE:-/tmp/claimtest-results.txt}"

# ── reporting ────────────────────────────────────────────────────────────
_result() {                      # _result PASS|FAIL|SKIP id "claim" "evidence"
  printf '%s %s — %s\n' "$1" "$2" "$3"
  [ -n "${4:-}" ] && printf '    %s\n' "$4"
  printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "${4:-}" >> "$RESULTS_FILE"
}
pass() { _result PASS "$@"; }
fail() { _result FAIL "$@"; }
skip() { _result SKIP "$@"; }
evidence() { printf '    > %s\n' "$*"; }

# ── sandbox helpers ──────────────────────────────────────────────────────
# Run a shell command inside the sandbox; prints output, returns its rc.
# Wrapped in `timeout`: right after creation the CLI can hang forever if it
# races the supervisor's SSH relay, and --timeout only bounds the command.
# stdin is closed on purpose: with it left open the exec often never returns.
sb_exec() {
  timeout -k 5 "$(( ${SB_EXEC_TIMEOUT:-60} + 30 ))" \
    openshell sandbox exec -n "$SB" --timeout "${SB_EXEC_TIMEOUT:-60}" -- sh -c "$*" </dev/null 2>&1
}

# The control: the same container and uid entered with kubectl exec, so the
# process has neither OpenShell's Landlock domain nor its seccomp filters, only
# what Kubernetes gives the pod. A result that differs between sb_exec and
# ctl_exec is OpenShell's doing; one that is the same is not.
ctl_exec() {
  local pns pname; read -r pns pname < <(sb_pod)
  [ -z "$pname" ] && { echo "no sandbox pod"; return 1; }
  timeout 90 kubectl -n "$pns" exec "$pname" -c agent -- env HOME=/sandbox sh -c "$*" </dev/null 2>&1
}

# Run a local script inside the sandbox or the control (shipped base64 on argv).
sb_script()  { sb_exec  "echo $(base64 -w0 "$1") | base64 -d > /tmp/.ct.sh && sh /tmp/.ct.sh; rm -f /tmp/.ct.sh"; }
ctl_script() { ctl_exec "echo $(base64 -w0 "$1") | base64 -d > /tmp/.ct.sh && sh /tmp/.ct.sh; rm -f /tmp/.ct.sh"; }

# value of "key value" lines printed by those scripts
kv() { echo "$1" | awk -v k="$2" '$1==k {sub(/^[^ ]+ /,""); print; exit}'; }

sb_phase() { openshell sandbox get "$SB" 2>/dev/null | awk '/PHASE|Phase|phase/{print $NF; exit}'; }

sb_wait_ready() {                # sb_wait_ready [seconds]
  local t="${1:-180}" i=0
  while [ $i -lt "$t" ]; do
    openshell sandbox list 2>/dev/null | grep -E "^\s*$SB\s" | grep -q Ready && return 0
    sleep 3; i=$((i+3))
  done
  return 1
}

# Ready means the pod is up; the supervisor's exec relay follows a few seconds
# later, so also wait until a trivial exec answers.
sb_exec_ready() {                # sb_exec_ready [seconds]
  local t="${1:-120}" i=0
  while [ $i -lt "$t" ]; do
    [ "$(SB_EXEC_TIMEOUT=10 sb_exec 'echo ready' | tail -1)" = "ready" ] && return 0
    sleep 3; i=$((i+3))
  done
  return 1
}

sb_create() {
  if ! openshell sandbox list 2>/dev/null | grep -qE "^\s*$SB\s"; then
    openshell sandbox create --name "$SB" --from "$SB_IMAGE" --no-tty --detach "$@" -- sleep 7200 >/dev/null 2>&1
  fi
  sb_wait_ready 240 && sb_exec_ready 120
}

sb_delete() { openshell sandbox delete "$SB" >/dev/null 2>&1 || true; }

# Pod backing the sandbox (namespace and name), for host-side checks.
sb_pod() { kubectl get pods -A --no-headers 2>/dev/null | awk -v s="$SB" '$2 ~ ("--" s "$") {print $1, $2; exit}'; }

# Supervisor pod = the enforcement layer for this sandbox (separate pod).
sb_supervisor_pod() {
  kubectl -n openshell get pods -l openshell.ai/boundary-role=supervisor \
    -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[0].env[?(@.name=="OPENSHELL_SANDBOX")].value}{"\n"}{end}' 2>/dev/null \
    | awk -v s="$SB" '$2==s{print $1; exit}'
}

# Poll a shell condition (as a string) inside the guest until true or timeout.
wait_until() {                   # wait_until <seconds> <command...>
  local t="$1" i=0; shift
  while [ $i -lt "$t" ]; do "$@" && return 0; sleep 3; i=$((i+3)); done
  return 1
}
