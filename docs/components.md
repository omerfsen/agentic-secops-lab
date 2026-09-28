# Component inventory

Every component named in SUSE's post and the deeper SUSE article it links to,
grouped by layer, with its licence.

**Code licence and commercial access are different things.** SLES and Rancher Prime
are open-source code sold by subscription; NIM is proprietary software. Both cost
money, only one is closed. The tables below record the licence, not the price.

## SUSE platform

| component | role | licence |
|---|---|---|
| SUSE AI Factory | control plane — deploys blueprints, lifecycle, prerequisites | commercial product |
| Blueprints | immutable app bundles that also carry the sandbox security policy | not stated |
| SLES | host OS | open source, subscription access |
| RKE2 | Kubernetes distribution | Apache 2.0 |
| Rancher Prime | cluster management | open source (Rancher), subscription access |
| Fleet | declarative GitOps across clusters | Apache 2.0 |
| SUSE Security | runtime scanning — this is NeuVector | Apache 2.0, paid Prime support tier |
| SUSE Observability | collects OTLP traces — StackState-based | closed; CE announced for 2027 |

## NVIDIA Open Agent Safety Platform

| component | role | licence |
|---|---|---|
| OpenShell | per-agent sandbox: out-of-process proxy, credential injection, Landlock + seccomp, default-deny egress, OCSF audit logs | Apache 2.0 |
| NemoClaw | attach to a running sandbox without holding cluster credentials | Apache 2.0 |
| Sentry | out-of-band monitoring, threat detection, millisecond quarantine | not stated — NVIDIA calls it a reference *system design*, not software |
| DOCA | DPU policy engine enforcing L3/L4/L7 rules | proprietary; requires NVIDIA DPUs or adapters |
| DOCA Argus | host-memory anomaly detection | NVIDIA library, announced June 2026 |
| BlueField-4 DPU | separate compute domain so policy survives host compromise | hardware |
| Vera CPU | Arm, 88 Olympus cores, Arm CCA confidential computing | hardware |

## Agents and orchestration

| component | role | licence |
|---|---|---|
| NeMo Agent Toolkit | agent topologies, async jobs, checkpoint/resume | Apache 2.0 |
| AI-Q | read-only research agents for triage and advisory lookup | Apache 2.0 |
| NeMo Guardrails | rails applied to every model call | Apache 2.0 |
| NeMo Relay | records agent activity, exports OTel or ATIF traces | Apache 2.0 |
| SUSE SecOps agents | survey, triage, research orchestrator, source router, researcher workers, writer, citation verifier, clarifier, remediation, validation, guardrail | not stated; ships via AI Factory |

## Models and inference

| component | role | licence |
|---|---|---|
| Nemotron 3 Ultra | plans, routes, synthesises | open weights — NVIDIA Open Model License |
| Nemotron 3.5 Lightning | high-volume triage and research fan-out | open weights, data and recipes — OpenMDW-1.1 |
| NIM | serves models behind an OpenAI-compatible API | proprietary; NVIDIA AI Enterprise licence |
| NeMo Retriever | searches advisories, errata, SBOMs, runbooks | runs as NIM microservices, so commercial |
| GPU Operator | GPU software stack on Kubernetes nodes | Apache 2.0 |

## Learning loop

Turns human approve/reject decisions into training data so the smaller model takes
over routine cases.

| component | licence |
|---|---|
| NeMo Data Store | NGC microservice; open-source licence not confirmed |
| NeMo Evaluator | SDK is Apache 2.0; the microservice is a closed NGC container |
| NeMo Customizer | NGC microservice; open-source licence not confirmed |

## Kernel features and open standards

| component | licence |
|---|---|
| Landlock | Linux kernel, GPL-2.0 |
| seccomp | Linux kernel, GPL-2.0 |
| OpenTelemetry / OTLP | CNCF, Apache 2.0 |
| OCSF (audit-log schema) | Apache 2.0 |

## Integrated today vs announced

Only part of NVIDIA's safety platform is wired in so far.

| | |
|---|---|
| **Integrated** | OpenShell, NemoClaw, NeMo Agent Toolkit, AI-Q, Guardrails, Relay, NeuVector, Fleet, RKE2 |
| **Announced, not integrated** | Sentry, DOCA, BlueField-4, Vera — the hardware-enforced second line |

SUSE describes OpenShell on its own as a complete deployment, which is what makes a
single-VM build meaningful rather than a toy.

## Gaps

- Neither article names the Git server, issue tracker or image catalogue the agents
  actually operate on.
- **Charter** and **Tower** appear in the threat table of the deeper article — seemingly
  agent authentication and connection gating — and are never explained. They look like
  Sentry components. (**Argus** turned out to be real: DOCA Argus, announced June 2026.)
- The SecOps agent blueprints have no public repository. Without AI Factory access you
  would rebuild the pipeline from the open pieces rather than deploy SUSE's.

## Sources

- SUSE, *We Gave Our Agents Autonomy. Here's How We Kept Control* — <https://www.suse.com/c/we-gave-our-agents-autonomy-heres-how-we-kept-control/>
- The deeper SUSE article linked from it, which adds RKE2, GPU Operator, NeMo Guardrails, seccomp and OCSF
- NVIDIA's OpenShell, NeMo Agent Toolkit and AI-Q repositories
- NVIDIA Open Model License; OpenMDW-1.1

Licences were read from the projects' own repositories and licence pages. Where a
component is distributed only as an NGC container and no licence is published, the
table says so rather than guessing.
