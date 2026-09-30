# Verifying SUSE's claims on this lab

SUSE's two articles make concrete claims about how the agents are kept under
control. Every claim that can be exercised on a single VM has a script here
that creates a real OpenShell sandbox on the lab cluster and checks the
behaviour, printing `PASS`, `FAIL` or `SKIP` with the evidence it saw. The
scripts assert what the articles and OpenShell's own docs say — not what the
lab happens to do — so a `FAIL` is a finding, not a bug in the test.

Sources:

- [We Gave Our Agents Autonomy. Here's How We Kept Control][post]
- [Agentic SecOps on SUSE AI Factory with NVIDIA Agent Safety Platform][deep]
- [OpenShell default policy][policy]

## Claims and tests

| # | claim (quoted) | source | test |
|---|---|---|---|
| 1 | "deny-by-default and hot-reloadable. The remediation agent can reach the Git server and the internal model endpoint and nothing else"; "A human must approve" | deep, post | `t01-egress-default-deny.sh` — the sandbox cannot reach `example.com`; the supervisor turns the attempt into a pending rule; after `openshell rule approve-all` the same request succeeds in the same pod, once the supervisor's next settings poll (about 10 s) picks the policy up |
| 2 | "access is restricted to allowed paths through Landlock … no writing to shell profiles or cron" | deep | `t02-landlock-filesystem.sh` — writes under `/etc`, `/usr`, `/etc/profile`, `/etc/cron.d` fail with permission denied; `/tmp` and the workspace are writable |
| 3 | "process behaviour through seccomp, both locked when the sandbox is created: no sudo, no setuid path" | deep | `t03-no-privilege-path.sh` — `NoNewPrivs: 1` and a seccomp filter on the sandbox process, no usable `sudo` |
| 4 | "zero direct git merges or Kubernetes API calls" | post | `t04-no-cluster-access.sh` — no service-account token in the sandbox, the API server is unreachable from it |
| 5 | "dynamically injects real credentials at the network boundary so raw tokens never sit inside the agent environment" | post, deep | `t05-credentials-proxied.sh` — imports `claimtest-echo.profile.yaml` (same shape as the [upstream examples](https://github.com/NVIDIA/OpenShell/tree/main/providers)), creates a provider holding a fake secret, attaches it to a sandbox; the sandbox's environment and filesystem never contain the secret, while an in-cluster echo service named as the profile's endpoint receives it in the `Authorization` header |
| 6 | "every decision lands in an OCSF-formatted audit log"; "logged by the enforcement layer, not by the agent" | deep | `t06-ocsf-audit-log.sh` — the deny and allow decisions from test 1 appear as `OCSF NET:OPEN … DENIED/ALLOWED` events in the log of the sandbox's supervisor pod, a separate pod the agent cannot reach (see test 4). In OpenShell 0.1.2 these are OCSF-classified event lines (class, activity, severity, decision, reason or policy), not JSON documents; nothing that looks like an audit file is visible from inside the sandbox |
| 7 | NeuVector / SUSE Security does runtime scanning of the workloads | post | `t07-neuvector-sees-sandbox.sh` — the NeuVector controller's REST API lists the sandbox pod in its workload inventory. Authenticates with a NeuVector API key (`NV_APIKEY`, preferred) or the admin password (`NV_PASSWORD`); skipped without either |

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
== ./t01-egress-default-deny.sh
    > before approval: curl https://example.com -> HTTP '000' (000 = connect refused by the supervisor)
    > pending rules: allow_example_com_443
    > after approve-all: HTTP 200 within 9s; sandbox pod start time unchanged (…)
PASS t01 — egress deny-by-default, human-approved, hot-reloadable
    denied before approval, allowed 9s after approve-all, same sandbox (no restart)
```

The recorded run is in [results.md](results.md).

[post]: https://www.suse.com/c/we-gave-our-agents-autonomy-heres-how-we-kept-control/
[deep]: https://www.suse.com/c/agentic-secops-on-suse-ai-factory-with-nvidia-agent-safety-platform/
[policy]: https://docs.nvidia.com/openshell/latest/how-it-works/policies/default-policy
