#!/bin/bash
# Claim 1: egress is deny-by-default, a human approves what the agent may
# reach, and approvals apply hot (no sandbox restart).
. "$(dirname "$0")/lib.sh"
ID=t01; CLAIM="egress deny-by-default, human-approved, hot-reloadable"
HOST=example.com
http() { sb_exec "curl -sS -m 8 -o /dev/null -w '%{http_code}' https://$HOST" | tail -1; }
pending_for_host() { openshell rule get "$SB" --status pending 2>/dev/null | grep -qiE 'example[._]com'; }
reaches() { [ "$(http)" = "200" ]; }

read -r pns pname < <(sb_pod)
start=$(kubectl -n "$pns" get pod "$pname" -o jsonpath='{.status.startTime}' 2>/dev/null)

code=$(http)
evidence "before approval: curl https://$HOST -> HTTP '$code' (000 = connect refused by the supervisor)"
[ "$code" = "200" ] && { fail $ID "$CLAIM" "sandbox reached https://$HOST with no rule approved"; exit 0; }

if ! wait_until 30 pending_for_host; then
  fail $ID "$CLAIM" "denied, but no pending rule for $HOST appeared within 30s for a human to approve"; exit 0
fi
evidence "pending rules: $(openshell rule get "$SB" --status pending 2>/dev/null | grep -E '^\s*Rule:' | awk '{print $2}' | tr '\n' ' ')"

t0=$(date +%s)
openshell rule approve-all "$SB" >/dev/null 2>&1
if wait_until 60 reaches; then
  dt=$(( $(date +%s) - t0 ))
  start2=$(kubectl -n "$pns" get pod "$pname" -o jsonpath='{.status.startTime}' 2>/dev/null)
  evidence "after approve-all: HTTP 200 within ${dt}s; sandbox pod start time unchanged ($start2)"
  [ "$start" = "$start2" ] && pass $ID "$CLAIM" "denied before approval, allowed ${dt}s after approve-all, same sandbox (no restart)" \
                            || fail $ID "$CLAIM" "allowed after approval but the sandbox pod restarted"
else
  fail $ID "$CLAIM" "still blocked 60s after approve-all: HTTP '$(http)'"
fi
