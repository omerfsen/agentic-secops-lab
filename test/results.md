# Claim test results — 2026-10-01T00:48Z

Guest: secops-lab · SUSE Linux Enterprise Server 16.0 · 6.12.0-160000.37-default · gateway 0.1.2 · image docker.io/nicolaka/netshoot:latest

| result | test | claim | evidence |
|---|---|---|---|
| PASS | t01 | egress deny-by-default; an approved rule opens one host without a restart | denied by the supervisor and held without approval; allowed 7s after approve-all in the same pod; an unapproved host stays blocked |
| PASS | t02 | Landlock restricts file access beyond what Unix permissions already block | 6 paths open to uid 10001 in the control are refused in the sandbox; system paths and system-wide profiles are refused in both; the workspace login profile stays writable |
| PASS | t03 | OpenShell seccomp filters on top of Kubernetes defaults; setuid binaries do not raise privilege | calls Kubernetes allows are refused only in the sandbox (6 filters vs 1); no root uid, no capabilities, a setuid-root binary stays uid 10001 |
| PASS | t04 | no Kubernetes credential in the sandbox and no path to the API server | no token mounted or projected; both API addresses refused by the supervisor |
| PASS | t05 | credentials injected at the network boundary, never inside the sandbox | the agent holds only a placeholder before and after the call; the upstream received the real token; node-side scans of the container found nothing |
| PASS | t06 | network allow/deny decisions recorded as OCSF events by the enforcement layer | the deny and the allow for example.com are OCSF NET:OPEN events in the supervisor pod's log |
| FAIL | t06b | filesystem (Landlock) denials recorded as OCSF events too | Landlock denied the write and nothing was logged; only network decisions reach the audit log |
| PASS | t07 | NeuVector monitors the sandbox at runtime (sees the processes it runs) | NeuVector tracks the running sandbox container and recorded a process started inside it within 0s |
