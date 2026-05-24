# QEMU Autoinstall Harness

This harness builds a disposable Arch ISO with this repository embedded, boots it
with QEMU, runs `install.sh` non-interactively against a qcow2 disk, then boots
the installed disk and waits for a serial login or systemd target.

## Host Prerequisites

On Arch:

```bash
sudo pacman -S --needed archiso qemu-full swtpm edk2-ovmf just rsync
```

The harness uses:

- UEFI via OVMF
- TPM 2.0 via `swtpm`
- QEMU user-mode networking
- serial logs under `.vm/qemu`

## Run

Smoke test, skipping AUR and dotfiles:

```bash
just vm-test
```

Full test, including AUR and dotfiles:

```bash
just vm-test-full
```

Useful lower-level commands:

```bash
just vm-build-iso
just vm-install
just vm-boot-check
just vm-clean
```

## Logs

```text
.vm/qemu/install.serial.log
.vm/qemu/boot.serial.log
```

The smoke test uses fixed VM-only credentials:

```text
root password: archtest
user: k
user password: archtest
LUKS passphrase: archtest
```
