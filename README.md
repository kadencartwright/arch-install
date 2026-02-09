# Arch Install Scripts

This repository contains helper scripts to configure new Arch Linux machines.

Current install profile:
- LUKS on LVM
- systemd-boot
- dracut

## Usage

Run from the Arch ISO as root:

```bash
./install.sh
```

### Optional flags

- `--disk /dev/nvme0n1`
- `--hostname myhost`
- `--username k`
- `--timezone America/Chicago`
- `--confirm-destroy /dev/nvme0n1`
- `--root-password-file /path/to/root_password`
- `--user-password-file /path/to/user_password`
- `--luks-password-file /path/to/luks_passphrase`
- `--non-interactive`

For non-interactive usage, provide required values plus `--confirm-destroy` with the exact disk path.

## Testing in QEMU/KVM

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
- runs `install.sh` in non-interactive mode on `/dev/vda`
- exits non-zero if install fails

Notes:
- Requires host packages: `qemu-system-x86_64`, `qemu-img`, `expect`, `rsync`.
- It is best-effort and depends on serial-console behavior of the Arch ISO.
- Use `--keep` to retain VM artifacts/logs for debugging.

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
