# NixOS Migration Guide

This repository now includes a NixOS migration path that mirrors the Arch installer layout:

- GPT disk with EFI partition + LUKS container
- LUKS on LVM (`vg1/root` + `vg1/home`)
- `systemd-boot`
- NetworkManager, Hyprland desktop stack, dotfiles bootstrap
- optional one-time TPM2 enrollment for LUKS unlock

## Layout

- `flake.nix`: primary Nix entrypoint and checks
- `hosts/arch-host/default.nix`: host composition
- `modules/*.nix`: functional split (storage, boot, users, desktop, bootstrap)
- `scripts/run-nixos-anywhere.sh`: unattended installer wrapper
- `scripts/postinstall-check.sh`: remote validation script

## Unattended install

Example:

```bash
./scripts/run-nixos-anywhere.sh \
  --disk /dev/vda \
  --confirm-destroy /dev/vda \
  --hostname nixos-test \
  --target root@192.168.122.50 \
  --username k \
  --timezone America/Chicago \
  --root-password-file /tmp/root_password \
  --user-password-file /tmp/user_password \
  --luks-password-file /tmp/luks_password
```

Dry-run command rendering:

```bash
./scripts/run-nixos-anywhere.sh ... --dry-run
```

## Post-install validation

```bash
./scripts/postinstall-check.sh --target k@192.168.122.50 --username k --hostname nixos-test
```

## Package parity notes

This migration prioritizes nixpkgs-native packages first. The following previous AUR entries are expected to need custom packaging or alternatives and are deferred:

- `bemoji`
- `bluetuith-bin`
- `reflector-simple`
- `tmux-sessionizer-bin`
- `ttf-apple-emoji`
- `ttf-segoe-ui-variable`
- `dracut-ukify` (not needed in this NixOS initrd approach)

`spotify` is mapped to nixpkgs `spotify` where available.

## Security handling

- Password and LUKS secrets are passed as one-time install inputs.
- The installer hashes root and user passwords before generating the ephemeral install flake.
- Temporary plaintext secret artifacts are deleted on script exit.
- TPM enrollment service deletes one-time LUKS key material after enrollment.
