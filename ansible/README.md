# Ansible

Two playbooks, because this is two machines with different credentials and
different ways of going wrong.

| | runs on | does |
|---|---|---|
| `host.yml` | the KVM host — **Ubuntu 24.04 LTS or SLES** | verifies GPU passthrough is possible, binds vfio-pci, creates the VM |
| `guest.yml` | the VM — **SLES** | SCC registration, NVIDIA driver, Landlock check, single-node RKE2 |

Only the guest has to be SLES. The host role detects the OS and picks the right
package manager, initrd tool and bootloader command, so an Ubuntu workstation
with the GPU in it is a normal setup.

## Not tested

**None of this has been run.** It was written from SUSE's and NVIDIA's published
material without access to SLES, a GPU or a SUSE subscription. Treat it as an
executable version of the notes in `../docs/`, not as something known to work.
Run `--check` first, read what it intends to do, and expect to fix things.

Corrections are the most useful contribution this repo can receive.

## Setup

```bash
cd ansible
cp inventory.example.ini inventory.ini
cp group_vars/all.example.yml group_vars/all.yml
$EDITOR group_vars/all.yml        # SCC code, IP, GPU PCI ids, image URL
```

Find the GPU's PCI addresses — you need **both** functions, the GPU and its
HDMI audio device:

```bash
lspci -nn | grep -i nvidia
```

Then:

```bash
ansible-playbook host.yml --check
ansible-playbook host.yml
# reboot the host if it asks, then run it again
ansible-playbook guest.yml --private-key .keys/secops-lab_ed25519 -u sles
```

## The SSH key

`host.yml` generates a dedicated ed25519 keypair at `.keys/<vm_name>_ed25519` on
the machine you run Ansible from, and installs the public half via cloud-init. It
is not reused across VMs and it is gitignored.

```bash
ssh -i .keys/secops-lab_ed25519 sles@192.168.1.50
```

Re-running is safe: an existing key is reused rather than replaced.

## What the checks are for

Three assertions fail the play rather than warning, because each produces a
system that looks fine and isn't:

- **IOMMU group isolation.** Passthrough is all-or-nothing per group. If the GPU
  shares a group with an NVMe controller, you either hand over both or move the
  card. The play lists the group contents before failing.
- **No host driver on the GPU.** If `nouveau` or the NVIDIA host driver holds the
  card, the guest gets a device it cannot initialise.
- **Landlock active in the guest.** OpenShell defaults to `best_effort`, so a
  missing LSM degrades enforcement silently — a sandbox that reports healthy and
  enforces nothing. This is the one most worth automating.

## Network

Bridged with a static address, set in `group_vars/all.yml` and applied by
cloud-init. The bridge (`br0` by default) must already exist on the host — these
playbooks don't reconfigure host networking, since getting that wrong costs you
access to the machine.

## Where it stops

At a single-node RKE2 cluster with the GPU visible to the guest. GPU Operator,
NeuVector, OpenShell and the agent stack are documented in `../docs/` but not
automated: OpenShell is alpha and the SUSE SecOps blueprints aren't public, so
automating them now would encode guesses.
