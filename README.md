# Arch Install Scripts

This repository contains helper scripts to configure new Arch Linux machines.

Current install profile:
- LUKS on LVM
- systemd-boot
- dracut

## Usage (Ansible)

Run from the Arch ISO as root:

```bash
./scripts/run-ansible-install.sh \
  --disk /dev/vda \
  --confirm-destroy /dev/vda \
  --hostname arch-test \
  --username k \
  --timezone America/Chicago \
  --root-password-file /tmp/root_password \
  --user-password-file /tmp/user_password \
  --luks-password-file /tmp/luks_password
```

### Flags

- `--disk /dev/nvme0n1`
- `--confirm-destroy /dev/nvme0n1`
- `--hostname myhost`
- `--username k`
- `--timezone America/Chicago`
- `--root-password-file /path/to/root_password`
- `--user-password-file /path/to/user_password`
- `--luks-password-file /path/to/luks_passphrase`
- `--disable-tpm-enroll`

Legacy shell installer (`./install.sh`) is still available, but Ansible is now the primary flow.

## Testing in QEMU/KVM

### Get or Build Arch ISO

Download from official Arch mirror infrastructure and verify:

```bash
./scripts/arch-iso.sh download
```

Build locally with `mkarchiso`:

```bash
./scripts/arch-iso.sh build
```

See options:

```bash
./scripts/arch-iso.sh --help
```

Use the VM harness to create an ephemeral test machine:

```bash
./scripts/start-test-vm.sh --iso /path/to/archlinux-x86_64.iso --headless
```

Defaults:
- 8G RAM
- 4 vCPUs
- 80G ephemeral qcow2 disk
- host repo shared into guest via `9p` (`hostshare` tag)

Inside the Arch live VM:

```bash
mkdir -p /mnt/host
mount -t 9p -o trans=virtio,version=9p2000.L hostshare /mnt/host
rsync -a --delete /mnt/host/ /root/arch-install/
cd /root/arch-install
printf 'rootpass' > /tmp/root_password
printf 'userpass' > /tmp/user_password
printf 'lukspass' > /tmp/luks_password
./install.sh --disk /dev/vda --hostname arch-test --username k \
  --timezone America/Chicago --root-password-file /tmp/root_password \
  --user-password-file /tmp/user_password --luks-password-file /tmp/luks_password \
  --confirm-destroy /dev/vda --non-interactive
```

Why this flow:
- `9p` gives instant access to your working tree without host-side upload steps.
- `rsync` inside the guest creates a writable isolated copy for destructive tests.
- the VM disk is disposable, so every run starts from a clean target.

### Unattended (CI-style) run

You can run an end-to-end installer test from the host using `expect`:

```bash
./scripts/run-vm-ci-test.sh --iso /path/to/archlinux-x86_64.iso
```

This script:
- boots a headless VM (`8G` RAM, `4` vCPU, `80G` ephemeral disk)
- mounts the repo over `9p`
- copies to `/root/arch-install` with `rsync`
- installs Ansible in the live ISO if needed
- runs `scripts/run-ansible-install.sh` on `/dev/vda`
- exits non-zero if install fails

Notes:
- Requires host packages: `qemu-system-x86_64`, `qemu-img`, `expect`, `rsync`.
- It is best-effort and depends on serial-console behavior of the Arch ISO.
- Use `--keep` to retain VM artifacts/logs for debugging.
- Use `--installer shell` to run the legacy shell flow instead.

## TODO

Set up TPM auto-unlocking:
- use `systemd-cryptenroll`
- configure dracut with TPM modules

Set up UKI generation:
- `yay -S dracut-ukify`

Set up lid-switch suspend config:
- `/etc/systemd/logind.conf`
- `HandleLidSwitch=suspend`
- `HandleLidSwitchExternalPower=ignore`
- `HandleLidSwitchDocked=ignore`

## Simple NixOS Install (No Flakes)

If you want a classic `/etc/nixos/configuration.nix` workflow:

1. Boot NixOS installer ISO
2. Prepare secret files (`root`, `user`, `luks`) on the live system
3. Run one script from this repo

Example from a checked-out repo on the ISO environment:

```bash
./scripts/install-nixos.sh \
  --disk /dev/nvme0n1 \
  --confirm-destroy /dev/nvme0n1 \
  --hostname twi-carbon \
  --username k \
  --timezone America/Chicago \
  --root-password-file /tmp/install-secrets/root_password \
  --user-password-file /tmp/install-secrets/user_password \
  --luks-password-file /tmp/install-secrets/luks_password \
  --reboot
```

Install behavior:
- prompts interactively for missing values via `gum` (auto-installs `gum` if missing)
- partitions disk as EFI + LUKS + LVM (`vg1/root`, `vg1/home`)
- generates `hardware-configuration.nix`
- writes `/etc/nixos/configuration.nix` from `nixos/configuration.nix.template`
- runs `nixos-install`

After boot, updates are standard:

```bash
cd /etc/nixos
sudo git pull
sudo nixos-rebuild switch
```

Remote one-liner from ISO (replace repo URL):

```bash
curl -fsSL https://raw.githubusercontent.com/<you>/<repo>/main/scripts/install-nixos.sh -o /tmp/install-nixos.sh && \
chmod +x /tmp/install-nixos.sh && \
/tmp/install-nixos.sh --help
```
