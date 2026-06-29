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
- `--x1c-power-workaround` (add ThinkPad X1 Carbon power workaround kernel params)
- `--non-interactive`
- `--dry-run`

## Safety behavior

- Requires explicit destructive confirmation before disk wipe (unless `--confirm-destroy` is passed).
- Unmounts all target-disk partitions and disables swap for them before formatting.
- Uses deterministic partition naming for SATA/NVMe/MMC devices.
- Uses root-only secret handoff files for chroot stage and removes them on exit.
- Temporarily grants wheel `NOPASSWD` for post-install user actions and restores sudoers on exit.

## Live ISO bootstrap

From the Arch live ISO, you can launch an interactive installer wrapper with:

```bash
curl -fsSL https://raw.githubusercontent.com/kadencartwright/arch-install/main/scripts/bootstrap-live.sh | sh
```

The bootstrap script prompts for:

- target disk, shown with stable `/dev/disk/by-id/...` paths where available
- hostname
- username
- timezone
- whether to install AUR packages
- whether to install dotfiles
- whether to apply ThinkPad X1 Carbon power workaround kernel params
- root password
- user password
- LUKS passphrase

It clones this repo into `/tmp/arch-install`, writes temporary root-only secret files, asks for a final `ERASE` confirmation, and then runs `install.sh`.

Useful overrides:

```bash
curl -fsSL https://raw.githubusercontent.com/kadencartwright/arch-install/main/scripts/bootstrap-live.sh \
  | REPO_REF=main INSTALL_DIR=/tmp/arch-install sh
```

## Supply-chain notes

- `install-yay.sh` and `install-dotfiles.sh` support ref pinning through env vars:
  - `YAY_REF`
  - `DOTFILES_REF`
  - `DOTMAN_REF`
- If refs are not set, scripts log explicit unpinned-source warnings.
