#!/bin/bash
# Claim 3: process behaviour is locked through seccomp when the sandbox is
# created; no sudo, no setuid path. Probes run in the sandbox and in the control
# (same container and uid, Kubernetes' RuntimeDefault seccomp profile only).
. "$(dirname "$0")/lib.sh"
ID=t03; CLAIM="OpenShell seccomp filters on top of Kubernetes defaults; setuid binaries do not raise privilege"
P="$(dirname "$0")/probes/priv.py"
run() { echo "echo $(base64 -w0 "$P") | base64 -d > /tmp/.ct.py && python3 /tmp/.ct.py; rm -f /tmp/.ct.py"; }
sbx=$(sb_exec "$(run)"); ctl=$(ctl_exec "$(run)")
echo "$sbx" | grep -q '^DONE$' || { fail $ID "$CLAIM" "sandbox probe did not complete: $(echo "$sbx" | tail -2 | tr '\n' ' ' | cut -c1-150)"; exit 0; }
echo "$ctl" | grep -q '^DONE$' || { fail $ID "$CLAIM" "control probe did not complete: $(echo "$ctl" | tail -2 | tr '\n' ' ' | cut -c1-150)"; exit 0; }

uid=$(kv "$sbx" uid); cap=$(kv "$sbx" capeff); nnp=$(kv "$sbx" nnp); f=$(kv "$sbx" filters); f1=$(kv "$sbx" pid1_filters)
evidence "sandbox: uid=$uid CapEff=$cap NoNewPrivs=$nnp seccomp filters=$f (sandbox PID 1: $f1); control: filters=$(kv "$ctl" filters) NoNewPrivs=$(kv "$ctl" nnp)"
evidence "setuid(self): sandbox=$(kv "$sbx" setuid_self) control=$(kv "$ctl" setuid_self); memfd_create: sandbox=$(kv "$sbx" memfd_create) control=$(kv "$ctl" memfd_create)"
evidence "setuid-root /bin/mount (mode $(kv "$sbx" mount_mode)) ran with Uid $(kv "$sbx" mount_uid); sudo is $(kv "$sbx" sudo) in this image, so 'no sudo' is not exercised"

bad=""
echo "$uid" | grep -qE '(^|,)0(,|$)' && bad="$bad root-uid"
[ "$cap" = "0000000000000000" ] || bad="$bad caps=$cap"
[ "$nnp" = "1" ] || bad="$bad no_new_privs=$nnp"
for c in setuid_self memfd_create; do
  [ "$(kv "$sbx" $c)" = "Operation_not_permitted" ] || bad="$bad $c-allowed-in-sandbox"
  [ "$(kv "$ctl" $c)" = "ok" ] || bad="$bad $c-also-refused-in-control"
done
mu=$(kv "$sbx" mount_uid); [ -n "$mu" ] && echo "$mu" | grep -qE '(^|,)0(,|$)' && bad="$bad setuid-mount-gained-root"
if [ -z "$bad" ]; then
  pass $ID "$CLAIM" "calls Kubernetes allows are refused only in the sandbox ($f filters vs $(kv "$ctl" filters)); no root uid, no capabilities, a setuid-root binary stays uid 10001"
else
  fail $ID "$CLAIM" "failed checks:$bad"
fi
