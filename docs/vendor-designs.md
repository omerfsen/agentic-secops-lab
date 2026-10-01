# NVIDIA, SUSE and Red Hat: three designs around one runtime

All three vendors build on the same agent sandbox, NVIDIA OpenShell. NVIDIA
supplies the parts and a reference design; SUSE and Red Hat each wrap those
parts in their own platform for a different use case. This page puts the
three side by side, with this repository's single-VM build as the last
column.

| Layer | NVIDIA's reference | SUSE's design | Red Hat's design | This repository |
|---|---|---|---|---|
| **Role** | Supplies the parts and a reference design | Builds a SecOps product on those parts | Builds a secure agent workspace for each employee | SUSE's design on one machine |
| **Platform** | Any: laptop, on-premises, cloud or Kubernetes | SLES, RKE2, Rancher Prime | OpenShift 4.22 or later | SLES 16, RKE2 |
| **Isolation unit** | Sandbox per agent; the reference design adds one VM per user | Sandbox pod per agent, each with a supervisor pod | One VM per user, OpenShell and its sandboxes inside | Sandbox pod per agent, in one VM |
| **Agent sandbox** | OpenShell | OpenShell | OpenShell | OpenShell 0.1.2, tested |
| **Identity** | Sentry gives every agent a verifiable identity, on BlueField-4 | Not detailed | Keycloak sign-in per user | None yet |
| **Secrets** | OpenShell providers | OpenShell providers | Vault with External Secrets Operator | OpenShell providers, tested |
| **Policy and approvals** | Human approval, or automatic approval within set limits | Approved in the OpenShell CLI | Policy in Git, applied by Argo CD | Approved in the CLI, tested |
| **Audit** | Allow and deny log, collected centrally | OCSF log into SUSE Observability | OCSF denials | OCSF log of network decisions in the supervisor pod, tested; filesystem denials are not logged |
| **Watching from outside** | Sentry on BlueField-4, keeps working if the host is compromised | NeuVector on every pod | Not in the pattern | NeuVector installed |
| **Model** | Any; Nemotron and NeMo Guardrails offered | Nemotron on NIM, local | External providers by default, vLLM optional | Nemotron Nano on vLLM, local |
| **Agents** | Claude Code, Codex, OpenCode, Copilot CLI, OpenClaw, NemoClaw, or your own | SUSE SecOps blueprints | NemoClaw, OpenClaw | None yet |
| **Hardware** | BlueField-4 DPU and Vera CPU, both optional | Vera-based systems as the target | Standard OpenShift nodes | Ryzen and one RTX 4080 SUPER |

"Tested" means one of the scripts in [test/](../test/) exercises it; see
[test/results.md](../test/results.md).

## How the designs relate

- **NVIDIA defines two lines of defence.** OpenShell is the software line and
  runs anywhere. Sentry on BlueField-4 is the hardware line, and it keeps
  working even if the host is taken over. Vera only makes sandboxes faster.
  NVIDIA's own FAQ says OpenShell does not need BlueField-4.
- **SUSE wraps the software line for security operations.** The agents do
  SecOps work, the model stays in-house, and NeuVector plus SUSE
  Observability watch the whole cluster around the sandboxes.
- **Red Hat wraps it for developers.** Every person gets their own agent in
  their own VM, built from a Fedora bootc golden image, with company sign-in
  and secrets from Vault. The model may live outside, because Red Hat's
  stated principle is to keep reasoning with a provider and execution on
  infrastructure the customer controls. A VM needs 4 cores, 8 GiB and
  40 GiB, plus 8 cores and 16 GiB for the cluster services.
- **Neither SUSE nor Red Hat has the hardware line yet.** Both name Sentry on
  BlueField-4 as the next step.

## Where this repository sits

It covers the software line, the layer every design shares, and the claim
tests exercise it. The OpenShell parts should behave the same wherever
OpenShell runs, but they have only been checked here. Structurally it resembles one of Red Hat's per-user VMs: one VM
holding OpenShell and its sandboxes, except that it runs RKE2 and a local
model inside. The gaps are the ones in the README's "What's next": sign-in,
real agents, and NeuVector's vulnerability scanning of the sandboxes. The hardware
line needs BlueField-4 and is out of reach on a workstation.

## Sources

- NVIDIA, [Open Agent Safety Platform](https://www.nvidia.com/en-us/solutions/ai/agent-safety/)
  and its [announcement](https://nvidianews.nvidia.com/news/open-agent-safety-platform)
- NVIDIA, [Secure Agent Workspace reference design, OpenShift Virtualization implementation](https://docs.nvidia.com/enterprise-reference-architectures/secure-agent-workspace-reference-design/latest/openshift-virtualization-reference-implementation.html)
- SUSE, [We Gave Our Agents Autonomy. Here's How We Kept Control](https://www.suse.com/c/we-gave-our-agents-autonomy-heres-how-we-kept-control/)
- SUSE, [Agentic SecOps on SUSE AI Factory with NVIDIA Agent Safety Platform](https://www.suse.com/c/agentic-secops-on-suse-ai-factory-with-nvidia-agent-safety-platform/)
- Red Hat, [Why Red Hat is building secure agent onboarding](https://www.redhat.com/en/blog/why-red-hat-is-building-secure-agent-onboarding)
- Red Hat, [Red Hat AI and OpenShell: Driving security-enhanced agent execution for enterprise AI](https://www.redhat.com/en/blog/red-hat-ai-and-openshell-driving-security-enhanced-agent-execution-for-enterprise-ai)
- Red Hat, [Secure Agent Workspace validated pattern](https://github.com/validatedpatterns-sandbox/secure-agent-workspace)
