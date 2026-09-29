#!/bin/bash
# Claim 2: filesystem access is restricted through Landlock — no writing to
# system paths, shell profiles or cron; /tmp and the workspace are writable.
. "$(dirname "$0")/lib.sh"
ID=t02; CLAIM="Landlock: system paths, shell profiles and cron are not writable"

denied=0; allowed=0; notes=""
for p in /etc/claimtest /usr/bin/claimtest /etc/profile /etc/cron.d/claimtest /root/.bashrc; do
  out=$(sb_exec "( : >> $p ) 2>&1 && echo WROTE || echo BLOCKED");
  if echo "$out" | grep -q WROTE; then notes="$notes $p=WRITABLE"; else denied=$((denied+1)); notes="$notes $p=denied"; fi
done
for p in /tmp/claimtest \$HOME/claimtest; do
  out=$(sb_exec "( : > $p ) 2>&1 && echo WROTE || echo BLOCKED")
  if echo "$out" | grep -q WROTE; then allowed=$((allowed+1)); notes="$notes $p=ok"; else notes="$notes $p=BLOCKED"; fi
done
lsm=$(sb_exec "cat /sys/kernel/security/lsm 2>/dev/null" | tail -1)
evidence "kernel LSMs seen from the sandbox: ${lsm:-n/a}"
evidence "writes:$notes"

if [ "$denied" -eq 5 ] && [ "$allowed" -ge 1 ]; then
  pass $ID "$CLAIM" "5/5 protected paths denied, $allowed/2 scratch paths writable"
else
  fail $ID "$CLAIM" "$denied/5 protected paths denied, $allowed/2 scratch paths writable:$notes"
fi
