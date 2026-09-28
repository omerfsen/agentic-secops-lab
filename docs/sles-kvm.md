# SLES on KVM

For the SUSE half this is a supported base. SUSE's RKE2 v1.36 support matrix
validates:

| | validated |
|---|---|
| SLES | **16.0**, 15 SP7, 15 SP6 |
| SL Micro | 6.2, 6.1, 6.0 |
| arch | x86_64 and arm64 |

(15 SP5 appeared in older matrices and has since dropped off — check the matrix
for the RKE2 version you actually install.) SUSE's AI deployment guide treats a GPU
fully passed through to a SLES VM as a normal topology.

Source: <https://www.suse.com/suse-rke2/support-matrix/all-supported-versions/rke2-v1-36>

The one non-SUSE runtime, OpenShell, lists only Debian/Ubuntu as supported hosts — so
run its gateway on RKE2 via the Helm chart rather than the bare-host path.

## Getting SLES without a subscription

SUSE offers a **60-day trial**. Register at <https://www.suse.com/download/sles/>,
tick the option asking for a registration code, and one is issued against your
email address. That code activates updates through SUSE Customer Center, which is
exactly what `scc_regcode` in `ansible/group_vars/all.yml` wants.

SLES 16.0 is listed among the available releases. The download links themselves are
behind an SCC login, so the qcow2 URL is something you paste into your own vars file
rather than something this repo can ship.

Two consequences worth planning around:

- **The clock starts at registration**, not at first boot. Register when you are
  ready to build, not while reading.
- **After 60 days the repositories stop**, so `zypper` can no longer install or
  patch. The running system keeps working; you just cannot change it. If the lab
  is going to outlive the trial, budget for a subscription or rebuild on
  openSUSE Leap, accepting that it is no longer the validated combination.

## Which SLES

**Use SLES 16.0.** It is validated by the current RKE2 matrix, and its 6.12 kernel has
the Landlock network rules and scoping that came after the 6.4 kernel in 15 SP6/SP7.
Since the whole point of this stack is that the sandbox — not the agent — holds the
boundary, taking the weaker Landlock is a poor trade.

15 SP6 and SP7 remain validated and will work; SUSE's own AI guide (written for
SUSE AI 1.0) recommends 15 SP6 or SL Micro 6.1. You just get less from Landlock.

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

The host does **not** have to be SLES — only the guest does. Ubuntu 24.04 LTS is a
perfectly good host, and is what this was worked out on. The differences are
mechanical:

| | Ubuntu 24.04 | SLES |
|---|---|---|
| packages | `qemu-kvm libvirt-daemon-system virtinst ovmf genisoimage` | `libvirt qemu-kvm virt-install cdrtools` |
| initrd | `update-initramfs -u -k all` | `dracut -f --regenerate-all` |
| bootloader | `update-grub` | `grub2-mkconfig -o /boot/grub2/grub.cfg` |

```bash
# kernel cmdline, either host
intel_iommu=on iommu=pt       # or: amd_iommu=on
```

**Intel and AMD behave differently here, and the difference bites people.** On
Intel, VT-d being on in firmware is usually not enough by itself — the kernel
still needs `intel_iommu=on` on the cmdline, or `/sys/kernel/iommu_groups` stays
empty even though the BIOS setting is correct. AMD-Vi more often self-enables
once the firmware setting is on, with no cmdline flag at all — confirmed on the
Ryzen 9900X this was worked out on: 29 populated IOMMU groups with no
`amd_iommu=on` anywhere in `/proc/cmdline`. `iommu=pt` is a host-side DMA
performance optimisation either way, not what gates whether groups appear —
don't mistake "groups are empty" for "iommu=pt is missing" and add it expecting
that alone to fix it, particularly on Intel.

Check what you actually have before assuming either way:

```bash
cat /proc/cmdline                          # what's actually set
ls /sys/kernel/iommu_groups/ | wc -l        # 0 = IOMMU is not active, full stop
```

`ansible/roles/kvm_host` asserts on the second one and refuses to continue if
it's zero — it won't guess at which cmdline flag you're missing, since that
depends on vendor.

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

## Host memory

A 96 GB host splits comfortably as 64 GB guest / 32 GB host. The guest wants the
larger share because MoE expert offload spills into system RAM — see
[gpu-sizing.md](gpu-sizing.md). Below about 48 GB in the guest, offload stops being
a viable route and you are choosing between a 9B model in VRAM or nothing.

## Caveat

SUSE's guidance puts Rancher, Observability and AI workloads on **separate clusters**
in production. A single VM is a lab layout by definition.
