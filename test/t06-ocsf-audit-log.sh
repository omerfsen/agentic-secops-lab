#!/bin/bash
# Claim 6: "every decision lands in an OCSF-formatted audit log", written by the
# enforcement layer, not by the agent. Run after t01, which leaves a deny and an
# allow for example.com. Two results: network decisions (t06), and whether a
# filesystem decision is logged at all (t06b).
. "$(dirname "$0")/lib.sh"
ID=t06; CLAIM="network allow/deny decisions recorded as OCSF events by the enforcement layer"
HOST='example\.com'

sup=$(sb_supervisor_pod)
[ -z "$sup" ] && { fail $ID "$CLAIM" "no supervisor pod found for sandbox $SB"; exit 0; }
log=$(kubectl -n openshell logs "$sup" --tail=5000 2>/dev/null)
denied=$(echo "$log" | grep -cE "OCSF NET:OPEN \[[A-Z]+\] DENIED .* -> $HOST:443 ")
allowed=$(echo "$log" | grep -cE "OCSF NET:OPEN \[[A-Z]+\] ALLOWED .* -> $HOST:443 ")
json=$(openshell settings get "$SB" 2>/dev/null | grep -i ocsf | tr -s ' ' | head -2 | tr '\n' ' ')
evidence "enforcement layer = pod $sup, separate from the sandbox pod; NET:OPEN decisions for example.com: $denied DENIED, $allowed ALLOWED"
echo "$log" | grep -E "OCSF NET:OPEN \[[A-Z]+\] (DENIED|ALLOWED) .* -> $HOST:443 " | sed -E 's/^[^ ]+ //' | sort -u | head -2 | while read -r l; do evidence "$l"; done
evidence "format: OCSF-classified one-line events (class, activity, severity, decision); the OCSF JSON sink setting: ${json:-not set (off by default)}"
if [ "$denied" -ge 1 ] && [ "$allowed" -ge 1 ]; then
  pass $ID "$CLAIM" "the deny and the allow for example.com are OCSF NET:OPEN events in the supervisor pod's log"
elif [ "$denied" -ge 1 ]; then
  fail $ID "$CLAIM" "deny logged but no ALLOWED event for example.com (did t01 pass?)"
else
  fail $ID "$CLAIM" "no OCSF network decision events for example.com in the supervisor log"
fi

# t06b: a decision that only Landlock makes (t02 showed /var/tmp is writable
# for uid 10001 without Landlock). Is it recorded anywhere?
ID=t06b; CLAIM="filesystem (Landlock) denials recorded as OCSF events too"
t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
res=$(sb_exec ': >> /var/tmp/ct-audit-probe 2>&1 && echo WROTE || echo DENIED; rm -f /var/tmp/ct-audit-probe')
sleep 3
new=$(kubectl -n openshell logs "$sup" --since-time="$t0" 2>/dev/null; openshell logs "$SB" --since 1m 2>/dev/null)
hits=$(echo "$new" | grep -E 'OCSF' | grep -cE 'var/tmp|FILE|FS:|FILESYSTEM|LANDLOCK')
evidence "write to /var/tmp from the sandbox: $(echo "$res" | tail -1); OCSF lines mentioning it or a filesystem class since: $hits"
if echo "$res" | grep -q WROTE; then
  fail $ID "$CLAIM" "the write was not denied, so there was no decision to log"
elif [ "$hits" -ge 1 ]; then
  pass $ID "$CLAIM" "the Landlock denial produced an OCSF record"
else
  fail $ID "$CLAIM" "Landlock denied the write and nothing was logged; only network decisions reach the audit log"
fi
