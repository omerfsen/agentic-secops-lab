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
mkdir -p group_vars/all
cp group_vars/all.example.yml group_vars/all/vars.yml
$EDITOR group_vars/all/vars.yml   # IP, GPU PCI ids, image URL, mode
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
ansible-playbook guest.yml
```

## Secrets

The SCC registration code doesn't live in `group_vars/all/vars.yml` in
plaintext — `vars.yml` just references `{{ vault_scc_regcode }}`, and the
real value sits encrypted in `group_vars/all/vault.yml` (ansible-vault). Both
files are in the `group_vars/all/` directory because Ansible loads every file
in there for the `all` group; a file called `group_vars/vault.yml` would be
looked up for a group named "vault" and silently ignored. The vault password
itself lives outside the repo entirely, at `~/.secops-lab-vault-pass`,
referenced by `vault_password_file` in `ansible.cfg` — so it survives
`git add -A`, archiving the repo, or anything else that scoops up the tree.

Setting it up from scratch:

```bash
openssl rand -base64 32 > ~/.secops-lab-vault-pass
chmod 600 ~/.secops-lab-vault-pass
echo 'vault_scc_regcode: "your-trial-code-here"' > group_vars/all/vault.yml
ansible-vault encrypt group_vars/all/vault.yml
```

`ansible-playbook` picks up both automatically via `ansible.cfg` — no
`--ask-vault-pass` needed. To read or edit it back:

```bash
ansible-vault view group_vars/all/vault.yml
ansible-vault edit group_vars/all/vault.yml
```

The whole `group_vars/all/` directory is gitignored on top of the vault
being encrypted — there's no reason to publish even the encrypted form of a
personal trial code.

## The SSH key

`host.yml` generates a dedicated ed25519 keypair at `.keys/<vm_name>_ed25519` on
the machine you run Ansible from, and installs the public half via cloud-init. It
is not reused across VMs and it is gitignored.

```bash
ssh -i .keys/secops-lab_ed25519 sles@192.168.1.50
```

Re-running is safe: an existing key is reused rather than replaced.

## Handing the GPU over

`gpu_passthrough_mode` in `group_vars/all/vars.yml` picks how the card reaches the
guest, and either choice is revertible.

- `permanent` (the default) blacklists the host driver and binds `vfio-pci`
  at boot — the first run stops and asks for a reboot, the second carries on
  into building the VM. Right for a headless box.
- `on-demand` (experimental) leaves the card with the host — its own
  driver, CUDA, `nvidia-smi` all keep working — and libvirt hands it to the
  guest only while the guest runs, via a hook installed under
  `/etc/libvirt/hooks/`. No reboot. It is refused outright unless another
  GPU is the firmware's primary display and nothing is plugged into the
  card: a live hand-over of a boot-VGA card with a monitor attached
  hard-froze a Ryzen 9900X / RTX 4080 SUPER host (last kernel line
  `vfio-pci: vgaarb: deactivate vga console`). `host.yml` rehearses the
  hand-over once so a setup that cannot do it fails there rather than at the
  first guest start; nothing may be using the card when the guest starts, or
  the hook refuses. `vm_autostart: false` is the sensible pairing. For a
  workstation, `permanent` plus `off` as a reboot-based toggle is the safer
  way to get the same "host keeps `nvidia-smi` between lab sessions" result.
- `off` undoes either: config removed, initrd rebuilt, host driver back
  after a reboot, and `host.yml` stops after the host checks instead of
  building a guest against a card the host still owns.

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

Bridged with a static address, set in `group_vars/all/vars.yml` and applied by
cloud-init. Defaults to `br10`, not `br0` — a fresh host sometimes already has
`br0` from something else, and `host_bridge` intentionally doesn't touch a
bridge it didn't create. If the bridge doesn't already exist on the host,
`host.yml` creates it — `host_bridge` moves the NIC currently carrying the
default route into the bridge via netplan and waits for the SSH connection to
come back before continuing. Netplan/Debian hosts only; on SLES, pre-build the
bridge yourself with wicked or NetworkManager and the role skips it, same as
it does on a re-run once the bridge exists. Already have a bridge you built by
hand? Nothing to do — it's left alone either way.

## Using the cluster

`guest.yml` leaves `kubectl` working for the login user inside the guest and
copies the admin kubeconfig to `ansible/<guest>.kubeconfig` on the machine
you ran it from, pointed at the guest's address (gitignored — it is cluster
admin). With `install_local_kubectl: true` it also drops a matching `kubectl`
into `/usr/local/bin` there.

```bash
export KUBECONFIG=$PWD/secops-lab.kubeconfig
kubectl get nodes
```

## The stack (`stack.yml`)

Part 3, once `guest.yml` has left a working RKE2: the public pieces of the
stack, one role each, each behind its own switch in `group_vars`.

| role | what it does | switch |
|---|---|---|
| `k8s_tools` | helm (SLES ships it), default StorageClass | always |
| `gpu_operator` | NVIDIA container toolkit on the node, GPU Operator with the driver and toolkit left host-managed, a CUDA job that proves a pod sees the card | `install_gpu_operator` |
| `neuvector` | SUSE Security from the upstream chart, single-node sizing | `install_neuvector` |

Two things the GPU role does that aren't in NVIDIA's docs, both learned on
SLES 16:

- SUSE's toolkit package sets `nvidia-container-cli` to run as `root:video`,
  and NVML then refuses with "insufficient permissions" even for root. The
  role switches it to `root:root`; the runtime re-reads the file per container.
- While that was broken, the first container start didn't fail — it wedged
  the runtime shim in the kernel (`uvm_va_space_destroy`, uninterruptible),
  every later NVML user queued behind it and the guest needed a hard reset.
  If GPU pods ever sit in `RunContainerError` with "context deadline
  exceeded", check for D-state `nvidia-container-runtime` processes before
  anything else.

## Where it stops

At a single-node RKE2 cluster with the GPU visible to the guest. One caveat
worth knowing in a security lab: SLES 16 enforces SELinux, and the tarball
install used here does not ship RKE2's SELinux policy, so the host enforces
but the containers run unconfined (no denials, everything works, nothing is
confined). Switching `INSTALL_RKE2_METHOD` to `rpm` pulls in `rke2-selinux`
and confines them — at the cost of a distro-specific RPM repo and a binary at
`/usr/bin/rke2` instead of `/usr/local/bin`. GPU Operator,
NeuVector, OpenShell and the agent stack are documented in `../docs/` but not
automated: OpenShell is alpha and the SUSE SecOps blueprints aren't public, so
automating them now would encode guesses.
