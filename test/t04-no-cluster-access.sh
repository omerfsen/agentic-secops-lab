#!/bin/bash
# Claim 4: zero direct Kubernetes API calls from an agent sandbox.
. "$(dirname "$0")/lib.sh"
ID=t04; CLAIM="no Kubernetes API access from the sandbox"

token=$(sb_exec "test -s /var/run/secrets/kubernetes.io/serviceaccount/token && echo TOKEN_MOUNTED || echo no-token" | tail -1)
api=$(sb_exec "curl -sk -m 6 -o /dev/null -w '%{http_code}' https://kubernetes.default.svc/version 2>&1 || echo blocked" | tail -1)
apiip=$(sb_exec "curl -sk -m 6 -o /dev/null -w '%{http_code}' https://10.43.0.1/version 2>&1 || echo blocked" | tail -1)
evidence "service-account token: $token; API by name: $api; API by cluster IP: $apiip"

if [ "$token" = "no-token" ] && ! echo "$api$apiip" | grep -qE '^(200|401|403)'; then
  pass $ID "$CLAIM" "no token mounted, API server unreachable by name and by IP"
else
  fail $ID "$CLAIM" "token=$token api=$api apiip=$apiip"
fi
