# Arch Install Scripts

Automation scripts for installing Arch Linux with:

- LUKS on LVM
- A single ext4 root filesystem that also contains `/home`
- systemd-boot
- dracut

All scripts are Bash-only (`#!/usr/bin/env bash`) and use strict mode.

## `install.sh` options

```bash
./install.sh \
  --disk /dev/nvme0n1 \
  --hostname my-host \
  --username k \
  --timezone America/Chicago
```

Supported flags:

- `--disk <path>`
- `--hostname <name>`
- `--username <name>` (default: `k`)
- `--timezone <tz>` (default: `America/Chicago`)
- `--confirm-destroy` (skip typed destructive confirmation)
- `--root-password-file <path>`
- `--user-password-file <path>`
- `--luks-passphrase-file <path>`
- `--non-interactive`
- `--dry-run`

## Safety behavior

- Requires explicit destructive confirmation before disk wipe (unless `--confirm-destroy` is passed).
- Unmounts all target-disk partitions and disables swap for them before formatting.
- Uses deterministic partition naming for SATA/NVMe/MMC devices.
- Uses root-only secret handoff files for chroot stage and removes them on exit.
- Temporarily grants wheel `NOPASSWD` for post-install user actions and restores sudoers on exit.

## Supply-chain notes

- `install-yay.sh` and `install-dotfiles.sh` support ref pinning through env vars:
  - `YAY_REF`
  - `DOTFILES_REF`
  - `DOTMAN_REF`
- If refs are not set, scripts log explicit unpinned-source warnings.
