# agentic-secops-lab

Notes on running the SUSE/NVIDIA agentic SecOps stack — the one described in
[*We Gave Our Agents Autonomy. Here's How We Kept Control*][suse-post] — on a
**single SLES KVM guest with one consumer GPU**.

Two things live here:

- **[Component inventory](docs/components.md)** — all 29 named components with their
  licences, and which are actually integrated today versus announced.
- **Install notes** — [what fits on one VM](docs/single-vm.md),
  [SLES and KVM setup](docs/sles-kvm.md), and [GPU sizing](docs/gpu-sizing.md).
- **[Ansible](ansible/)** — two playbooks: build the VM on the KVM host, then
  provision it. Untested; see its README.

## What this is not

This is **not** the reference architecture. SUSE's design assumes a datacentre:
multiple clusters, 8×H100-class inference for the planner model, and BlueField-4
DPUs enforcing policy in a separate compute domain. None of that fits on a
workstation.

It is also **not a completed build**. These are notes compiled from SUSE's and
NVIDIA's published material, worked through to the point of "would this deploy".
Where something is unverified it says so. Corrections welcome — open an issue.

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
