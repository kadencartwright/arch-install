# NixOS Config

This folder is the replacement path for the Arch install scripts. It defines a NixOS system named `laptop` using flakes, Home Manager, `disko`, and `sops-nix`.

## Build

```bash
nix flake check
nixos-rebuild build --flake .#laptop
```

## VM Test

```bash
nixos/scripts/vm-test.sh check
nixos/scripts/vm-test.sh dry-build
nixos/scripts/vm-test.sh build-vm
nixos/scripts/vm-test.sh run-vm
```

For an install-flow test against a disposable VM:

```bash
nixos/scripts/vm-test.sh install-vm
```

The harness copies `nixos/` to a temp directory by default so untracked local
files are visible to Nix during development. Use `--no-copy` after committing or
staging everything if you want to evaluate the repository path directly.

By default, temp files and VM disk images live under
`~/.cache/arch-install/nixos-vm-test`, which keeps them on `/home` instead of
root-backed `/tmp`. If `/nix` is also out of space, add `--local-store`:

```bash
nixos/scripts/vm-test.sh --local-store check
nixos/scripts/vm-test.sh --local-store build-vm
```

That uses a chroot Nix store under
`~/.cache/arch-install/nixos-vm-test/nix-root`.

## Install From The NixOS ISO

Find the target disk with:

```bash
ls -l /dev/disk/by-id/
```

Then run:

```bash
sudo nix --extra-experimental-features 'nix-command flakes' \
  run github:nix-community/disko/latest#disko-install -- \
  --flake github:kadencartwright/arch-install/main?dir=nixos#laptop \
  --write-efi-boot-entries \
  --disk main /dev/disk/by-id/<explicit-disk-id>
```

The optional wrapper is:

```bash
curl -fsSL https://raw.githubusercontent.com/kadencartwright/arch-install/<pinned-commit>/nixos/scripts/install-nixos.sh \
  | sudo HOST=laptop DISK=/dev/disk/by-id/<explicit-disk-id> REF=<pinned-commit> bash
```

Pin both the raw script URL and `REF` to a commit when installing real hardware.
