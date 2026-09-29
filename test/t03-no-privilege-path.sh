#!/bin/bash
# Claim 3: process behaviour is locked through seccomp at creation — no sudo,
# no setuid path.
. "$(dirname "$0")/lib.sh"
ID=t03; CLAIM="seccomp locked at creation: no sudo, no setuid path"

status=$(sb_exec "grep -E '^(NoNewPrivs|Seccomp|Uid):' /proc/self/status")
nnp=$(echo "$status" | awk '/NoNewPrivs/{print $2}')
scmp=$(echo "$status" | awk '/^Seccomp:/{print $2}')
uid=$(echo "$status" | awk '/^Uid:/{print $2}')
sudo_out=$(sb_exec "command -v sudo >/dev/null && sudo -n true 2>&1 && echo SUDO_WORKS || echo NO_SUDO" | tail -1)
setuid=$(sb_exec "find / -xdev -perm -4000 -type f 2>/dev/null | head -5 | tr '\n' ' '")
evidence "NoNewPrivs=$nnp Seccomp=$scmp (2 = filter) uid=$uid sudo=$sudo_out"
evidence "setuid binaries visible: ${setuid:-none}"

if [ "$nnp" = "1" ] && [ "$scmp" = "2" ] && [ "$sudo_out" = "NO_SUDO" ]; then
  pass $ID "$CLAIM" "no_new_privs set, seccomp filter active, sudo unusable"
elif [ "$sudo_out" = "NO_SUDO" ] && [ "$nnp" = "1" ]; then
  fail $ID "$CLAIM" "no_new_privs and no sudo, but no seccomp filter on the process (Seccomp=$scmp)"
else
  fail $ID "$CLAIM" "NoNewPrivs=$nnp Seccomp=$scmp sudo=$sudo_out"
fi
