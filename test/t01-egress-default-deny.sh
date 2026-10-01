#!/bin/bash
# Claim 1: egress is deny-by-default, a human approves what the agent may
# reach, and approvals apply hot (no sandbox restart).
. "$(dirname "$0")/lib.sh"
ID=t01; CLAIM="egress deny-by-default; an approved rule opens one host without a restart"
HOST=example.com
http() { sb_exec "curl -sS -m 8 -o /dev/null -w '%{http_code}' https://${1:-$HOST}" | tail -1; }
attempt() { sb_exec "curl -sS -m 8 -o /dev/null -w 'http=%{http_code} ' https://$1; echo rc=\$?" 2>&1 | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-160; }
pending_for_host() { openshell rule get "$SB" --status pending 2>/dev/null | grep -qiE 'example[._]com'; }
reaches() { [ "$(http)" = "200" ]; }

read -r pns pname < <(sb_pod)
[ -z "$pname" ] && { fail $ID "$CLAIM" "sandbox pod not found"; exit 0; }
start=$(kubectl -n "$pns" get pod "$pname" -o jsonpath='{.status.startTime}' 2>/dev/null)

evidence "before approval: curl https://$HOST -> $(attempt $HOST)"
code=$(http)
[ "$code" = "200" ] && { fail $ID "$CLAIM" "sandbox reached https://$HOST with no rule approved"; exit 0; }
sup=$(sb_supervisor_pod)
why=$(kubectl -n openshell logs "$sup" --tail=500 2>/dev/null | grep -E "NET:OPEN .*DENIED .*$HOST:443" | tail -1 | sed -E 's/^[^ ]+ //')
[ -z "$why" ] && { fail $ID "$CLAIM" "curl failed but the supervisor recorded no policy denial for $HOST"; exit 0; }
evidence "supervisor: $why"

if ! wait_until 30 pending_for_host; then
  fail $ID "$CLAIM" "denied, but no pending rule for $HOST appeared within 30s for a human to approve"; exit 0
fi
evidence "pending rules: $(openshell rule get "$SB" --status pending 2>/dev/null | grep -E '^\s*Rule:' | awk '{print $2}' | tr '\n' ' ')"
sleep 12   # longer than one policy poll: the block must persist without approval
code=$(http); [ "$code" = "200" ] && { fail $ID "$CLAIM" "$HOST opened without any approval"; exit 0; }
evidence "12 s later, still unapproved: HTTP $code"

t0=$(date +%s)
openshell rule approve-all "$SB" >/dev/null 2>&1
if wait_until 60 reaches; then
  dt=$(( $(date +%s) - t0 ))
  start2=$(kubectl -n "$pns" get pod "$pname" -o jsonpath='{.status.startTime}' 2>/dev/null)
  evidence "after approve-all: HTTP 200 within ${dt}s; sandbox pod start time unchanged ($start2)"
  other=$(http example.org)
  evidence "control after approval: https://example.org (never approved) -> HTTP $other"
  if [ "$other" = "200" ]; then fail $ID "$CLAIM" "approval opened more than the approved host (example.org reachable)"
  elif [ -n "$start" ] && [ "$start" = "$start2" ]; then pass $ID "$CLAIM" "denied by the supervisor and held without approval; allowed ${dt}s after approve-all in the same pod; an unapproved host stays blocked"
  else fail $ID "$CLAIM" "allowed after approval but the sandbox pod restarted"; fi
else
  fail $ID "$CLAIM" "still blocked 60s after approve-all: HTTP '$(http)'"
fi
