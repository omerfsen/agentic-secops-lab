#!/bin/bash
# Run the claim tests from the KVM host: copies test/ to the guest over the
# lab's SSH key and runs run.sh there as the login user. Pass NV_PASSWORD in
# the environment to enable the NeuVector test.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
inv="$repo/ansible/inventory.ini"
host=$(awk '/^\[sles_guest\]/{f=1;next} f && /ansible_host=/{for(i=1;i<=NF;i++) if($i ~ /^ansible_host=/) {sub("ansible_host=","",$i); print $i; exit}}' "$inv")
user=$(awk '/^\[sles_guest\]/{f=1;next} f && /ansible_user=/{for(i=1;i<=NF;i++) if($i ~ /^ansible_user=/) {sub("ansible_user=","",$i); print $i; exit}}' "$inv")
key="$repo/ansible/.keys/$(ls "$repo/ansible/.keys" | grep -E '_ed25519$' | head -1)"
ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i "$key")

echo "== copying test/ to $user@$host"
ssh "${ssh_opts[@]}" "$user@$host" 'mkdir -p ~/claimtest'
scp -q "${ssh_opts[@]}" "$here"/*.sh "$here"/*.yaml "$here"/README.md "$user@$host:~/claimtest/"
# NeuVector credentials for test 7 go over as a mode-600 file on stdin, never
# on a command line: NV_CRED_FILE (a local file with NV_APIKEY=/NV_PASSWORD=
# lines), or the NV_APIKEY / NV_PASSWORD variables. run.sh deletes the copy.
cred=""
if [ -n "${NV_CRED_FILE:-}" ] && [ -f "$NV_CRED_FILE" ]; then
  cred=$(cat "$NV_CRED_FILE")
elif [ -n "${NV_APIKEY:-}${NV_PASSWORD:-}" ]; then
  cred=$(printf 'NV_APIKEY=%s\nNV_PASSWORD=%s\n' "${NV_APIKEY:-}" "${NV_PASSWORD:-}")
fi
if [ -n "$cred" ]; then
  printf '%s\n' "$cred" | ssh "${ssh_opts[@]}" "$user@$host" 'umask 077; cat > ~/claimtest/.nv-credentials'
fi
echo "== running"
ssh -t "${ssh_opts[@]}" "$user@$host" "bash ~/claimtest/run.sh"
echo "== fetching results.md"
scp -q "${ssh_opts[@]}" "$user@$host:~/claimtest/results.md" "$here/results.md"
echo "saved to $here/results.md"
