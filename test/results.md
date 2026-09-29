# Claim test results — 2026-09-29T07:09Z

Guest: secops-lab · SUSE Linux Enterprise Server 16.0 · 6.12.0-160000.37-default · gateway 0.1.2 · image docker.io/nicolaka/netshoot:latest

| result | test | claim | evidence |
|---|---|---|---|
| PASS | t01 | egress deny-by-default, human-approved, hot-reloadable | denied before approval, allowed 9s after approve-all, same sandbox (no restart) |
| PASS | t02 | Landlock: system paths, shell profiles and cron are not writable | 5/5 protected paths denied, 2/2 scratch paths writable |
| PASS | t03 | seccomp locked at creation: no sudo, no setuid path | no_new_privs set, seccomp filter active, sudo unusable |
| PASS | t04 | no Kubernetes API access from the sandbox | no token mounted, API server unreachable by name and by IP |
| PASS | t05 | credentials injected at the boundary, never inside the sandbox | sandbox saw 'openshell:resolve:env:v7…', the upstream saw the real secret |
| PASS | t06 | allow/deny decisions recorded as OCSF events by the enforcement layer | deny and allow for example.com logged as OCSF NET:OPEN events in the supervisor pod |
| SKIP | t07 | NeuVector monitors the sandbox workload | could not log in to NeuVector at https://neuvector.192.168.50.50.sslip.io with the bootstrap secret; set NV_PASSWORD |
