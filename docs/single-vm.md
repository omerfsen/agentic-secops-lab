# What fits on a single VM

Short answer: the software tier fits, the model tier and the hardware tier don't.

## Fits

**Kubernetes.** SUSE's AI node installer supports single-node RKE2, and a GPU fully
passed through to a VM is a documented SLES / SL Micro topology. SUSE's own deep-dive
says the same Blueprints deploy to a workstation-class cluster, a datacentre, or the
edge — the blueprint is the unit, not the cluster size.

**OpenShell.** Two deployment modes:

- default — the whole gateway as a K3s cluster inside one Docker container
- Helm chart onto an existing cluster, Kubernetes 1.29+

Only the MicroVM sandbox driver needs KVM, so nested virtualisation is optional; the
Docker, Podman and Kubernetes drivers don't need it. Note its supported hosts are
listed as Debian/Ubuntu — on SLES, expect the Helm path rather than official support.

**Agents and security.** NeMo Agent Toolkit, AI-Q, Guardrails, Relay and NeuVector are
light CPU workloads. SUSE Observability is the heaviest optional piece, and it is
optional — the traces are plain OTLP, so any collector will take them.

**Models**, with caveats. NIM is free for development on up to 16 GPUs through the
Developer Program, or use vLLM. Which model fits depends entirely on the card — see
[gpu-sizing.md](gpu-sizing.md).

## Doesn't fit

**Nemotron 3 Ultra.** Self-hosting needs roughly 8×B200/GB200, 16×H100 or 8×H200.
Unless the "VM" is an 8-GPU cloud instance, substitute Lightning or Nano for the
planner role and accept worse routing decisions.

**Sentry, DOCA, BlueField-4, Vera.** Physical hardware, and not integrated yet in any
case. This is the second, hardware-enforced line of defence; SUSE describes OpenShell
alone as a complete deployment, so its absence changes the threat model rather than
breaking the build.

**The SecOps agent blueprints.** They ship through SUSE AI Factory with no public
repository. Without AI Factory access you rebuild the pipeline from the open pieces —
which is most of the work, and most of the learning.

## A workable lab spec

| | |
|---|---|
| vCPU | 16 |
| RAM | 64–128 GB (the upper end if you're offloading MoE experts to system RAM) |
| disk | 500 GB NVMe — model caches need real PVCs |
| GPU | one passed through; 24 GB for Lightning/Nano, 80 GB if you also want retrieval NIMs on the same card |

Treat it as a lab. SUSE's guidance is that production separates Rancher, Observability
and AI workloads onto different clusters, so a single VM is by definition not that.
And OpenShell is alpha — "one developer, one gateway".
