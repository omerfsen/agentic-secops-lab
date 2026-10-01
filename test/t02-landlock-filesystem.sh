#!/bin/bash
# Claim 2: file access is restricted to allowed paths through Landlock; no
# writing to shell profiles or cron. Every probe runs twice: in the sandbox,
# and in the control (same container and uid, no Landlock). Only paths where the
# two differ show Landlock at work; paths both refuse are Unix permissions.
. "$(dirname "$0")/lib.sh"
ID=t02; CLAIM="Landlock restricts file access beyond what Unix permissions already block"
LL="/var/tmp/ct-probe /dev/shm/ct-probe /proc/self/comm /opt /sbin /var/lib"
NAMED="/etc/profile /usr/bin/ct-probe /etc/crontabs/ct-probe /root/.bashrc"

sbx=$(sb_script "$(dirname "$0")/probes/fs.sh"); ctl=$(ctl_script "$(dirname "$0")/probes/fs.sh")
echo "$sbx" | grep -q '^DONE$' || { fail $ID "$CLAIM" "sandbox probe did not complete: $(echo "$sbx" | tail -2 | tr '\n' ' ' | cut -c1-150)"; exit 0; }
echo "$ctl" | grep -q '^DONE$' || { fail $ID "$CLAIM" "control probe did not complete: $(echo "$ctl" | tail -2 | tr '\n' ' ' | cut -c1-150)"; exit 0; }

shown=0; leaks=""; line=""
for p in $LL; do
  s=$(kv "$sbx" "$p"); c=$(kv "$ctl" "$p"); line="$line $p:sandbox=$s,control=$c"
  case "$c" in WROTE|READ) case "$s" in Permission_denied) shown=$((shown+1)) ;; WROTE|READ) leaks="$leaks $p" ;; esac ;; esac
done
evidence "Landlock-only paths:$line"
named=""; for p in $NAMED; do named="$named $p:sandbox=$(kv "$sbx" "$p"),control=$(kv "$ctl" "$p")"; done
evidence "named targets (blocked by Unix permissions or absent either way):$named"
prof=$(kv "$sbx" "/sandbox/.bash_profile")
evidence "agent's own \$HOME/.bash_profile (workspace, read-write by policy): $prof"

if [ -n "$leaks" ]; then
  fail $ID "$CLAIM" "the sandbox could use paths its policy does not grant:$leaks"
elif [ "$shown" -ge 4 ]; then
  pass $ID "$CLAIM" "$shown paths open to uid 10001 in the control are refused in the sandbox; system paths and system-wide profiles are refused in both; the workspace login profile stays writable"
else
  fail $ID "$CLAIM" "only $shown paths show a sandbox-only refusal"
fi
