# SLES on KVM

For the SUSE half this is a supported base: RKE2 v1.34's support matrix lists SLES
16.0 and 15 SP5–SP7 plus SL Micro 6.x, and SUSE's AI deployment guide treats a GPU
fully passed through to a SLES VM as a normal topology.

The one non-SUSE runtime, OpenShell, lists only Debian/Ubuntu as supported hosts — so
run its gateway on RKE2 via the Helm chart rather than the bare-host path.

## Which SLES

**Prefer SLES 16.0.** Its 6.12 kernel has the Landlock network rules and scoping that
landed after the 6.4 kernel in 15 SP6/SP7. SUSE's own guide (written for SUSE AI 1.0)
recommends 15 SP6 or SL Micro 6.1, which still work — you just get weaker Landlock.

**Verify Landlock is actually enabled**, because the failure is silent:

```bash
journalctl -kb -g landlock      # expect "Up and running"
cat /sys/kernel/security/lsm     # landlock must appear in the list
```

If it's missing, enable it at boot with the `lsm=` kernel parameter. This matters more
than it looks: OpenShell's policies default to Landlock `best_effort`, so a missing LSM
**degrades enforcement instead of failing loudly**. You get a sandbox that reports
healthy and isn't one.

## KVM host

```bash
# kernel cmdline
intel_iommu=on iommu=pt       # or: amd_iommu=on
```

- Bind the GPU's **entire IOMMU group** to `vfio-pci`, not just the GPU function
- Guest machine type `q35` with OVMF firmware
- CPU mode `host-passthrough`
- Enable Above-4G decoding for large-BAR datacentre cards
- Nested virtualisation **only** if you want OpenShell's MicroVM sandbox driver

Check the grouping before you commit to a board:

```bash
for d in /sys/kernel/iommu_groups/*/devices/*; do
  echo "group ${d%%/devices*}: $(lspci -nns ${d##*/})"
done | sort -V
```

Passthrough is 1:1 and needs no NVIDIA licence. Sharing one GPU across VMs means vGPU,
which does need a vGPU or NVAIE licence.

## Guest install order

1. **Register with SCC**, add the Containers module and the NVIDIA Compute module,
   install the G07 driver (Turing or newer), confirm `nvidia-smi`
2. **RKE2** server, single node, plus a StorageClass such as `local-path` — NIM model
   caches need PVCs
3. **Rancher** if you're using AI Factory (its charts come from the SUSE Application
   Collection, which needs subscription registration), then **GPU Operator** with
   `driver.enabled=false`, then **NeuVector**
4. **OpenShell** via Helm (Kubernetes 1.29+, Helm 3), then NemoClaw and the agent stack
5. **Model serving** — vLLM or llama.cpp; see [gpu-sizing.md](gpu-sizing.md)

SUSE's node installer can do steps 1–3 for a single node.

## Consumer GPU passthrough

If the card is a GeForce rather than a datacentre part:

- Pass **both PCI functions** — the GPU and its HDMI audio device — from the same
  IOMMU group. Consumer boards sometimes group them with unrelated devices, which is
  why you check `/sys/kernel/iommu_groups` first.
- Recent NVIDIA drivers no longer refuse to initialise in a VM, so the old
  KVM-hiding tricks (`kvm.ignore_msrs`, hypervisor CPUID masking) are unnecessary.
- If the guest driver still fails to initialise the card, try disabling Resizable BAR
  in host firmware.
- In the guest, blacklist `nouveau` and run headless — serial or virtio console.

SUSE's G07 driver covers Turing and newer, so a GeForce card is fine as far as the
driver is concerned. Licensing is the constraint, not support: see
[gpu-sizing.md](gpu-sizing.md#nim-licensing).

## Caveat

SUSE's guidance puts Rancher, Observability and AI workloads on **separate clusters**
in production. A single VM is a lab layout by definition.
