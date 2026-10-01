#!/bin/bash
# Claim 4: zero direct Kubernetes API calls from an agent sandbox. Checks that
# no cluster credential reaches the sandbox and that the API server cannot be
# reached; the reachability part rests on the same default-deny egress as t01.
. "$(dirname "$0")/lib.sh"
ID=t04; CLAIM="no Kubernetes credential in the sandbox and no path to the API server"
read -r pns pname < <(sb_pod)
[ -z "$pname" ] && { fail $ID "$CLAIM" "sandbox pod not found"; exit 0; }
automount=$(kubectl -n "$pns" get pod "$pname" -o jsonpath='{.spec.automountServiceAccountToken}')
projected=$(kubectl -n "$pns" get pod "$pname" -o jsonpath='{range .spec.volumes[*]}{.projected.sources[*].serviceAccountToken.path}{end}')
out=$(sb_exec 'test -s /var/run/secrets/kubernetes.io/serviceaccount/token && echo token=MOUNTED || echo token=none
for u in https://kubernetes.default.svc/version https://10.43.0.1/version; do
  c=$(curl -sk -m 6 -o /dev/null -w "%{http_code}" "$u"); echo "api $u http=$c rc=$?"; done; echo DONE')
echo "$out" | grep -q '^DONE$' || { fail $ID "$CLAIM" "probe did not complete: $(echo "$out" | tail -2 | tr '\n' ' ' | cut -c1-150)"; exit 0; }
tok=$(echo "$out" | sed -n 's/^token=//p')
evidence "pod spec: automountServiceAccountToken=$automount, projected token volumes: ${projected:-none}; in sandbox: token=$tok"
echo "$out" | grep '^api ' | while read -r l; do evidence "$l"; done
sup=$(sb_supervisor_pod); denied=$(kubectl -n openshell logs "$sup" --tail=3000 2>/dev/null | grep -cE 'NET:OPEN .*DENIED .*(kubernetes\.default\.svc|10\.43\.0\.1):443')
evidence "supervisor recorded $denied DENIED decisions for the API server (the default-deny egress of t01, not an API-specific rule)"
reached=$(echo "$out" | grep '^api ' | grep -vc 'http=000')
if [ "$automount" = "false" ] && [ -z "$projected" ] && [ "$tok" = "none" ] && [ "$reached" = "0" ]; then
  pass $ID "$CLAIM" "no token mounted or projected; both API addresses refused by the supervisor"
else
  fail $ID "$CLAIM" "automount=$automount projected=${projected:-none} token=$tok api_answered=$reached"
fi
