# agentic-secops-lab

**TL;DR** — the SUSE/NVIDIA agentic SecOps stack from
[*We Gave Our Agents Autonomy. Here's How We Kept Control*][suse-post],
rebuilt on **one workstation**: a SLES 16.0 KVM guest with a consumer GPU passed
through, RKE2, the NVIDIA GPU Operator, SUSE Security (NeuVector), vLLM serving
a Nemotron model, and NVIDIA OpenShell running a real agent sandbox. Three
Ansible playbooks build all of it from a fresh Ubuntu host and a SLES trial. A
[test directory](test/) then checks what SUSE says about the sandbox against
the running system and records the outcome in [test/results.md](test/results.md).

> **Need the GPU back on the host, or back in the guest?** The switch is one
> variable, one playbook and one reboot in either direction —
> **[docs/gpu-modes.md](docs/gpu-modes.md)**.

## What it is

A working, single-VM version of the public half of that architecture, built
and verified end to end, plus the notes and inventory that went into it:

- **The platform.** Ubuntu 24.04 KVM host with the GPU bound to vfio-pci,
  a SLES 16.0 guest on a bridged LAN address, NVIDIA G06 driver, RKE2 with
  Traefik ingress — all from `ansible/host.yml` and `ansible/guest.yml`.
- **The stack.** GPU Operator, NeuVector with its UI behind ingress, vLLM
  serving Nemotron Nano 9B (FP8) on the one GPU with an OpenAI-style API,
  and the OpenShell gateway with the Agent Sandbox CRDs and CLI — from
  `ansible/stack.yml`, each piece behind its own switch.
- **The proof.** Scripts under `test/` that create a sandbox and exercise
  the claims one by one: egress denied until a human approves a rule and
  allowed without a restart afterwards, Landlock keeping system paths and
  shell profiles read-only, seccomp with no privilege path, no Kubernetes API
  from inside, credentials injected by the supervisor rather than handed to
  the agent, and every decision recorded as an OCSF event outside the
  sandbox. Each test prints the evidence it saw.
- **The reading.** A component inventory with licences, what fits on one
  VM and what does not, GPU sizing, and how to move the GPU between host and
  guest.

What it costs to reproduce: one machine with a supported GPU, a
[60-day SLES trial](docs/sles-kvm.md#getting-sles-without-a-subscription),
and an afternoon.

What lives here:

- **[Component inventory](docs/components.md)** — all 29 named components with their
  licences, and which are actually integrated today versus announced.
- **Install notes** — [what fits on one VM](docs/single-vm.md),
  [SLES and KVM setup](docs/sles-kvm.md), [GPU sizing](docs/gpu-sizing.md),
  and [moving the GPU between host and guest](docs/gpu-modes.md).
- **[Ansible](ansible/)** — three playbooks: build the VM on the KVM host,
  provision it, then install the stack on it. See its README.
- **[Claim tests](test/)** — scripts that put SUSE's statements about the
  sandbox (deny-by-default egress, Landlock, seccomp, proxied credentials,
  OCSF audit) to the test on the running lab, with the
  [recorded results](test/results.md).

## How it fits together

```mermaid
flowchart TB
    op(["Operator: ansible, openshell CLI, kubectl, browser"])

    subgraph host["KVM host — Ubuntu 24.04"]
        br10["br10 bridge to the LAN"]
        vfio["vfio-pci owns the GPU<br>(mode: permanent, revertible)"]
        libvirt["libvirt / QEMU"]
    end

    subgraph guest["SLES 16.0 guest — one static LAN IP, GPU passed through"]
        drv["NVIDIA G06 driver<br>+ container toolkit"]
        rke2["RKE2 + Traefik ingress"]
        subgraph k8s["Workloads on RKE2"]
            gpuop["GPU Operator"]
            vllm["vLLM<br>Nemotron Nano 9B FP8"]
            nv["NeuVector<br>runtime security"]
            gw["OpenShell gateway<br>policies · rules · providers"]
            subgraph sbx["One agent sandbox"]
                agent["agent container<br>Landlock + seccomp, uid 10001"]
                sup["supervisor pod<br>DNS + transparent proxy<br>OCSF audit log"]
            end
        end
    end

    inet(("Internet<br>approved hosts only"))

    op -- "host.yml" --> host
    op -- "guest.yml · stack.yml over SSH" --> guest
    vfio --> libvirt --> drv --> gpuop --> vllm
    br10 --> rke2
    op -- "sandbox create · rule approve" --> gw
    gw -- "policy push, hot reload" --> sup
    agent -- "every connection<br>and DNS lookup" --> sup
    sup -- "allowed + credential injected" --> inet
    sup -- "internal model endpoint" --> vllm
    nv -. "watches every pod" .-> sbx
    op -- "sslip.io ingress: NeuVector UI, /vllm/v1" --> rke2
```

The agent never holds a credential and never talks to the network directly:
DNS answers are synthetic addresses that only the supervisor can route, so a
name that no approved rule covers is refused before a packet leaves the pod,
and the refusal shows up as a pending rule for a human. [test/](test/) shows
each of those steps happening.

## What this is not

This is **not** the reference architecture. SUSE's design assumes a datacentre:
multiple clusters, 8×H100-class inference for the planner model, and BlueField-4
DPUs enforcing policy in a separate compute domain. None of that fits on a
workstation.

It started as notes compiled from SUSE's and NVIDIA's published material,
worked through to the point of "would this deploy". It has since been built
for real on one machine — an Ubuntu 24.04 host with a Ryzen 9900X and an RTX
4080 Super, a SLES 16.0 guest — up to a running OpenShell sandbox, and the
Ansible encodes what that took. Where something is still unverified it says
so. Corrections welcome — open an issue.

Three specific limits worth knowing before you start:

| | |
|---|---|
| **OpenShell is alpha** | NVIDIA's own framing is "one developer, one gateway" |
| **The SecOps agents aren't public** | they ship as SUSE AI Factory blueprints; no public repo |
| **Nemotron 3 Ultra doesn't fit** | swap in Lightning or Nano for the planner role |

Host is Ubuntu 24.04 LTS, guest is SLES 16.0 — only the guest has to be SUSE, and
a [60-day trial](docs/sles-kvm.md#getting-sles-without-a-subscription) is enough to
build the whole thing.

## Why it's still worth doing

The interesting claim in SUSE's post is architectural, not about scale: agents get
autonomy because a sandbox holds the credentials and the egress policy, not because
the agent is trusted. That property is testable on one machine. The DPU layer adds
a second, hardware-enforced line — but SUSE describes OpenShell on its own as a
complete deployment.

## What's next

Things the lab is set up for but does not do yet, roughly in the order they
make sense:

- **Close the loop with NeuVector.** Run the seventh test with the admin
  password, then go further: have NeuVector's network rules and alerts
  react to a sandbox doing something denied, so both layers are visible in
  one run.
- **A real SecOps agent.** SUSE's remediation agent ships as a blueprint,
  not a repo. Build a small one: an agent inside a sandbox that reads
  NeuVector events through an approved rule, asks the local vLLM endpoint
  what to do, and proposes a change that a human approves. That is the
  article's whole loop on one machine.
- **NemoClaw.** NVIDIA's operator front end for OpenShell is now public.
  Attach it to this gateway and see what it adds over the raw CLI.
- **NeMo Guardrails** in front of the vLLM endpoint, so the model side has
  a policy too, not only the sandbox side.
- **Real users on the gateway.** Replace `allowUnauthenticatedUsers` with
  OIDC, and import real provider profiles (NVIDIA, OpenAI, GitHub) instead
  of the test's echo profile.
- **SELinux confinement for RKE2.** The tar install leaves containerd
  unconfined; the RPM install fixes that and is the supported path on SLES.
- **On-demand GPU mode.** Moving the card between host and guest without a
  reboot is written and gated off; it needs a second GPU or a non-boot GPU
  to be safe. See [docs/gpu-modes.md](docs/gpu-modes.md).
- **A bigger planner model** when the GPU allows it. Nemotron Nano stands in
  for Nemotron 3 here; [docs/gpu-sizing.md](docs/gpu-sizing.md) has the
  numbers.
- **A second VM** as a separate compute domain, to approximate what the DPU
  layer gives without the hardware.

## Learn more

The articles and the announcement:

- SUSE, [We Gave Our Agents Autonomy. Here's How We Kept Control][suse-post]
- SUSE, [Agentic SecOps on SUSE AI Factory with NVIDIA Agent Safety Platform](https://www.suse.com/c/agentic-secops-on-suse-ai-factory-with-nvidia-agent-safety-platform/)
- NVIDIA, [Open Agent Safety Platform announcement](https://nvidianews.nvidia.com/news/open-agent-safety-platform)
- [SUSE AI](https://www.suse.com/products/ai/) and [SUSE Security (NeuVector)](https://www.suse.com/products/neuvector/) product pages

The sandbox layer:

- [OpenShell on GitHub](https://github.com/NVIDIA/OpenShell) and the
  [OpenShell docs](https://docs.nvidia.com/openshell/latest/), in particular
  the [default policy](https://docs.nvidia.com/openshell/latest/how-it-works/policies/default-policy)
  and [provider profiles](https://docs.nvidia.com/openshell/latest/how-it-works/providers/profiles)
- [Agent Sandbox](https://github.com/kubernetes-sigs/agent-sandbox), the
  Kubernetes SIG project OpenShell builds on
- [NemoClaw](https://github.com/NVIDIA/NemoClaw),
  [NeMo Guardrails](https://github.com/NVIDIA/NeMo-Guardrails) and the
  [NeMo Agent Toolkit](https://github.com/NVIDIA/NeMo-Agent-Toolkit)
- [Landlock](https://docs.kernel.org/userspace-api/landlock.html) in the
  kernel docs, and the [OCSF schema](https://schema.ocsf.io/) the audit
  events are classified against

The platform underneath:

- [SLES 16.0 documentation](https://documentation.suse.com/sles/16.0/) and
  the [SLES download page](https://www.suse.com/download/sles/)
- [RKE2 docs](https://docs.rke2.io/) and [Traefik](https://doc.traefik.io/traefik/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/)
- [NeuVector docs](https://open-docs.neuvector.com/)
- [vLLM docs](https://docs.vllm.ai/) and the
  [Nemotron Nano 9B v2 FP8 model card](https://huggingface.co/nvidia/NVIDIA-Nemotron-Nano-9B-v2-FP8)
- [libvirt](https://libvirt.org/) for the KVM side

## Licence summary

By code licence, nearly everything in the pipeline is open source. The exceptions:

- **NIM** — needs an NVIDIA AI Enterprise licence (also serves NeMo Retriever)
- **SUSE Observability** — closed; SUSE has said a Community Edition lands in 2027
- **Nemotron models** — open *weights* under NVIDIA's Open Model License and
  OpenMDW-1.1, which is not the same as OSI-approved open source
- **Sentry / DOCA / BlueField-4 / Vera** — proprietary or hardware, and not
  integrated yet

SLES and Rancher Prime are open-source code sold by subscription — commercial
access, not a commercial licence. See [components.md](docs/components.md) for the
per-component breakdown.

## Sources

Everything here derives from SUSE's and NVIDIA's public material; nothing is quoted
at length. See [Sources](docs/components.md#sources).

[suse-post]: https://www.suse.com/c/we-gave-our-agents-autonomy-heres-how-we-kept-control/
