# Moving the GPU between the host and the guest

The card belongs to exactly one side at a time. `gpu_passthrough_mode` in
`ansible/group_vars/all/vars.yml` says which, `ansible/host.yml` applies it,
and every switch needs one reboot of the host. Nothing here is destructive:
the guest stays defined, its disk stays, and the two states can be flipped
back and forth as often as you like.

## Which state am I in?

```bash
lspci -nnk -s 01:00 | grep "in use"     # vfio-pci = guest owns it, nvidia = host owns it
nvidia-smi                              # works only while the host owns it
sudo virsh list --all                   # the guest is "running" only while it owns it
```

## Give the card back to the host (`off`)

Use this when you need the GPU on the host itself — CUDA, `nvidia-smi`,
anything that runs directly on the machine.

```bash
cd ~/projects/agentic-secops-lab/ansible
# group_vars/all/vars.yml → gpu_passthrough_mode: "off"
ansible-playbook host.yml
sudo reboot
```

What `host.yml` does in this mode:

- removes the vfio/blacklist modprobe config and rebuilds the initrd, so the
  next boot loads the NVIDIA driver on the host again
- disables the guest's autostart and sets its PCI hostdevs to
  `managed='no'` — libvirt will then refuse to start the guest while the
  host owns the card instead of trying to pull it away from the driver live
  (a live detach has hard-frozen this host once; that path is closed)
- stops after the host checks; it never touches the guest itself

After the reboot: `nvidia-smi` works on the host, the guest is shut off and
stays that way. Don't `virsh start` it in this state — it fails on purpose.

## Give the card to the guest again (`permanent`)

```bash
cd ~/projects/agentic-secops-lab/ansible
# group_vars/all/vars.yml → gpu_passthrough_mode: permanent
ansible-playbook host.yml       # writes the vfio config, rebuilds the initrd, stops at the reboot gate
sudo reboot
ansible-playbook host.yml       # passes the gate, re-enables autostart, starts the guest
```

After the second run the guest is up with the GPU, autostarts with the host,
and everything inside it (RKE2, the GPU Operator, vLLM, OpenShell) comes back
on its own — no `guest.yml` or `stack.yml` needed, they are idempotent and
only matter if you change something.

## What the reboot looks like

- With the host owning the card, the console and any monitor on the card
  work as before.
- With the guest owning it, the card's outputs are dark for the host from
  early boot; the host console lives on the iGPU (motherboard HDMI/DP, the
  IP-KVM). If you want BIOS/GRUB on the iGPU too, set the firmware's primary
  display to it.
- `nvidia-cdi-refresh.service` and `nvidia-persistenced.service` log a
  failure at boot while the guest owns the card. Harmless: there is no
  driver for them to talk to.
- The NVIDIA modules are refused outright in this mode, not only
  blacklisted. The driver package's udev rule would otherwise load them in a
  loop, every attempt failing, and flood the host console with
  `NVRM: GPU … is already bound to vfio-pci` several times a second.

## The experimental third state (`on-demand`)

Hands the card to the guest only while the guest runs and back to the host
when it stops, no reboot. It is refused on this host by design: the card is
the firmware's boot VGA device with a monitor attached, which is exactly the
setup that froze the machine. Details and the gates are in
[`ansible/README.md`](../ansible/README.md#handing-the-gpu-over).
