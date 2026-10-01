# Verifying SUSE's claims on this lab

SUSE's two articles make concrete claims about how the agents are kept under
control. Every claim that can be exercised on a single VM has a script here
that creates a real OpenShell sandbox on the lab cluster and checks the
behaviour, printing `PASS`, `FAIL` or `SKIP` with the evidence it saw.

Where a result could have another cause, the probe runs twice: in the
sandbox, and in a control, which is the same container and uid entered with
`kubectl exec`, so it has neither OpenShell's Landlock domain nor its seccomp
filters. Only what differs between the two is credited to OpenShell; what
both refuse is ordinary Unix permissions or Kubernetes defaults. Each claim
was also put to an adversarial review, one skeptic per test trying to make
it pass for the wrong reason, and the tests were rewritten until it could
not. A `FAIL` is a finding about the claim, not a bug in the test.

Sources:

- [We Gave Our Agents Autonomy. Here's How We Kept Control][post]
- [Agentic SecOps on SUSE AI Factory with NVIDIA Agent Safety Platform][deep]
- [OpenShell default policy][policy]

## Claims and tests

| # | claim (quoted) | source | what the test shows | not shown |
|---|---|---|---|---|
| 1 | "deny-by-default and hot-reloadable. The remediation agent can reach the Git server and the internal model endpoint and nothing else"; "A human must approve" | deep, post | `t01-egress-default-deny.sh`: the sandbox cannot reach `example.com`, and the supervisor logs why; the attempt becomes a pending rule; it is still blocked 12 s later; after `openshell rule approve-all` the same request succeeds in the same pod within about one 10 s policy poll; `example.org`, never approved, stays blocked | the Git-server and model-endpoint allowlist; who approves (the lab gateway runs without user identity); SUSE's human approval of the plan before a sandbox exists, which is a different gate |
| 2 | "access is restricted to allowed paths through Landlock … no writing to shell profiles or cron" | deep | `t02-landlock-filesystem.sh`: six paths the control can use as uid 10001 are refused in the sandbox (writes to `/var/tmp`, `/dev/shm`, `/proc/self/comm`; reads of `/opt`, `/sbin`, `/var/lib`). `/etc/profile`, `/usr/bin`, `/etc/crontabs` and `/root/.bashrc` are refused in both, by Unix permissions | the agent's own `$HOME/.bash_profile` sits in the read-write workspace and **is writable** under the default policy |
| 3 | "process behaviour through seccomp, both locked when the sandbox is created: no sudo, no setuid path" | deep | `t03-no-privilege-path.sh`: the sandbox process carries 6 seccomp filters against the control's 1; `setuid(self)` and `memfd_create`, which Kubernetes' default profile allows, are refused only in the sandbox; uid 10001 with no capabilities; the setuid-root `/bin/mount` runs as uid 10001 | sudo: the image has none, so "no sudo" is not exercised |
| 4 | "zero direct git merges or Kubernetes API calls" | post | `t04-no-cluster-access.sh`: the pod spec disables the service-account token and projects none; no token file; the API server is refused by name and by IP, by the same default-deny egress as test 1, not by an API-specific rule | direct git merges |
| 5 | "dynamically injects real credentials at the network boundary so raw tokens never sit inside the agent environment" | post, deep | `t05-credentials-proxied.sh`: a provider (profile `claimtest-echo.profile.yaml`, same shape as the [upstream examples](https://github.com/NVIDIA/OpenShell/tree/main/providers)) holds a random fake secret; inside the sandbox the variable is an `openshell:resolve:env:` placeholder; before and after a call, no match in the environment or files (searched with a pattern that never contains the secret), nor in any container process's environment or command line or in its files as seen from the node; the echo service's own log shows the real token arrived | that injection is limited to the endpoints and binaries the profile names |
| 6 | "every decision lands in an OCSF-formatted audit log"; "logged by the enforcement layer, not by the agent" | deep | `t06-ocsf-audit-log.sh`: the deny and the allow from test 1 are `OCSF NET:OPEN` events in the log of the sandbox's supervisor pod, a separate pod. They are one-line OCSF-classified events; the OCSF JSON sink (`ocsf_json_enabled`) is off by default. **t06b fails**: a write that only Landlock refuses leaves no record anywhere, so "every decision" holds for network decisions only | — |
| 7 | "We use SUSE Security for runtime scanning" | post | `t07-neuvector-sees-sandbox.sh`: NeuVector's controller API lists the running agent container (matched by pod name, namespace and UID) and records a uniquely named process started inside the sandbox in its process history. Authenticates with a NeuVector API key (`NV_APIKEY`, preferred) or the admin password (`NV_PASSWORD`); skipped without either | vulnerability scanning: NeuVector's auto-scan is off by default and was not enabled |

Not testable on this lab, and marked as such rather than faked: NemoClaw
attaching without cluster credentials (not installed), NeMo Guardrails and
Relay (not installed), the BlueField/DOCA/Sentry hardware line (not
integrated by NVIDIA yet either), and the SecOps blueprints themselves (no
public repository).

## Running

From the guest, as the login user (`openshell` and `kubectl` already work):

```bash
bash test/run.sh
```

From the KVM host, using the lab's SSH key (copies this directory over and
runs it there):

```bash
bash test/run-from-host.sh
NV_CRED_FILE=~/nv-credentials bash test/run-from-host.sh   # also runs test 7
```

Test 7 needs NeuVector credentials; the other six do not. Create an API key
in the NeuVector UI (Settings, API Keys, role `reader`) and put it in a
mode-600 file as `NV_APIKEY=<name>:<secret>`, or the admin password as
`NV_PASSWORD=…`. The file travels to the guest over SSH stdin, never on a
command line, and `run.sh` deletes the copy when it finishes. The
`NV_APIKEY` and `NV_PASSWORD` environment variables work too.

`run.sh` creates one sandbox called `claimtest` (image `nicolaka/netshoot`,
override with `SB_IMAGE`) plus a `claimtest` namespace for the echo service,
runs the tests in order, tears everything down including the provider and
profile, prints a summary and writes it to `test/results.md`. A single test
can be re-run on its own while the sandbox exists:
`bash test/t02-landlock-filesystem.sh`. The whole run takes about five
minutes, most of it image pulls and the sandbox becoming Ready.

## What a run looks like

Each test prints the evidence it collected, then its verdict:

```
== ./t02-landlock-filesystem.sh
    > Landlock-only paths: /var/tmp/ct-probe:sandbox=Permission_denied,control=WROTE … /opt:sandbox=Permission_denied,control=READ …
    > named targets (blocked by Unix permissions or absent either way): /etc/profile:sandbox=Permission_denied,control=Permission_denied …
    > agent's own $HOME/.bash_profile (workspace, read-write by policy): WROTE
PASS t02 — Landlock restricts file access beyond what Unix permissions already block
    6 paths open to uid 10001 in the control are refused in the sandbox; …
```

The recorded run is in [results.md](results.md).

[post]: https://www.suse.com/c/we-gave-our-agents-autonomy-heres-how-we-kept-control/
[deep]: https://www.suse.com/c/agentic-secops-on-suse-ai-factory-with-nvidia-agent-safety-platform/
[policy]: https://docs.nvidia.com/openshell/latest/how-it-works/policies/default-policy
