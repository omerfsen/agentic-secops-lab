#!/bin/bash
# Claim 6: every allow/deny decision lands in an OCSF-formatted audit log,
# written by the enforcement layer, not by the agent. Run after t01 so a deny
# and an allow for example.com exist.
. "$(dirname "$0")/lib.sh"
ID=t06; CLAIM="allow/deny decisions recorded as OCSF events by the enforcement layer"
HOST=example.com

sup=$(sb_supervisor_pod)
[ -z "$sup" ] && { fail $ID "$CLAIM" "no supervisor pod found for sandbox $SB"; exit 0; }
log=$(kubectl -n openshell logs "$sup" --tail=5000 2>/dev/null)
denied=$(echo "$log" | grep -E "OCSF NET:OPEN .*DENIED .*$HOST" | wc -l)
allowed=$(echo "$log" | grep -E "OCSF NET:OPEN .*ALLOWED .*$HOST" | wc -l)
total=$(echo "$log" | grep -c '^[0-9T:.Z-]* OCSF ')
evidence "enforcement layer = pod $sup (not the sandbox pod); $total OCSF events, $denied DENIED and $allowed ALLOWED for $HOST"
echo "$log" | grep -E "OCSF NET:OPEN .*(DENIED|ALLOWED) .*$HOST" | sed -E 's/^[^ ]+ //' | sort -u | head -2 | while read -r l; do evidence "$l"; done
# the agent cannot touch that log: no API access from inside (t04) and the log lives in another pod
in_sb=$(sb_exec "ls /var/log/openshell* /run/openshell/*.log 2>&1 | head -2" | tail -1)
evidence "audit files visible inside the sandbox: ${in_sb:-none}"

if [ "$denied" -ge 1 ] && [ "$allowed" -ge 1 ]; then
  pass $ID "$CLAIM" "deny and allow for $HOST logged as OCSF NET:OPEN events in the supervisor pod"
elif [ "$denied" -ge 1 ]; then
  fail $ID "$CLAIM" "deny logged but no ALLOWED event for $HOST (did t01 pass?)"
else
  fail $ID "$CLAIM" "no OCSF decision events for $HOST in the supervisor log"
fi
