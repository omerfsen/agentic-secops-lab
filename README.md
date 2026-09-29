# agentic-secops-lab

Notes on running the SUSE/NVIDIA agentic SecOps stack — the one described in
[*We Gave Our Agents Autonomy. Here's How We Kept Control*][suse-post] — on a
**single SLES KVM guest with one consumer GPU**.

> **Need the GPU back on the host, or back in the guest?** The switch is one
> variable, one playbook and one reboot in either direction —
> **[docs/gpu-modes.md](docs/gpu-modes.md)**.

Two things live here:

- **[Component inventory](docs/components.md)** — all 29 named components with their
  licences, and which are actually integrated today versus announced.
- **Install notes** — [what fits on one VM](docs/single-vm.md),
  [SLES and KVM setup](docs/sles-kvm.md), [GPU sizing](docs/gpu-sizing.md),
  and [moving the GPU between host and guest](docs/gpu-modes.md).
- **[Ansible](ansible/)** — three playbooks: build the VM on the KVM host,
  provision it, then install the stack on it. See its README.

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
