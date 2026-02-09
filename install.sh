#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf '[install] %s\n' "$*"
}

die() {
  printf '[install] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

prompt_secret() {
  local prompt="$1"
  local confirm_prompt="$2"
  local value
  local confirm

  while true; do
    if command -v gum >/dev/null 2>&1; then
      value="$(gum input --password --placeholder "$prompt")"
      confirm="$(gum input --password --placeholder "$confirm_prompt")"
    else
      read -r -s -p "$prompt" value
      printf '\n'
      read -r -s -p "$confirm_prompt" confirm
      printf '\n'
    fi

    if [[ -n "$value" && "$value" == "$confirm" ]]; then
      printf '%s' "$value"
      return 0
    fi

    log "Inputs do not match. Try again."
  done
}

prompt_value() {
  local prompt="$1"
  local value

  while true; do
    if command -v gum >/dev/null 2>&1; then
      value="$(gum input --placeholder "$prompt")"
    else
      read -r -p "$prompt" value
    fi

    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi

    log "Value is required."
  done
}

partition_path() {
  local disk="$1"
  local index="$2"
  if [[ "$disk" =~ (nvme|mmcblk) ]]; then
    printf '%sp%s' "$disk" "$index"
  else
    printf '%s%s' "$disk" "$index"
  fi
}

ensure_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run this script as root"
}

install_gum_if_needed() {
  if ! command -v gum >/dev/null 2>&1; then
    log "Installing gum"
    pacman -S --noconfirm --needed gum
  fi
}

cleanup() {
  if [[ -n "${TMP_CFG_DIR:-}" && -d "$TMP_CFG_DIR" ]]; then
    rm -rf "$TMP_CFG_DIR"
  fi
}
trap cleanup EXIT

ensure_root
require_cmd pacman
require_cmd timedatectl
require_cmd lsblk
require_cmd sgdisk
require_cmd mkfs.fat
require_cmd cryptsetup
require_cmd pvcreate
require_cmd vgcreate
require_cmd lvcreate
require_cmd mkfs.ext4
require_cmd mount
require_cmd genfstab
require_cmd arch-chroot
require_cmd tee

install_gum_if_needed

DISK=""
HOSTNAME=""
USERNAME="k"
TIMEZONE="America/Chicago"
NON_INTERACTIVE=0
CONFIRM_DESTROY=""
ROOT_PASSWORD_FILE=""
USER_PASSWORD_FILE=""
LUKS_PASSWORD_FILE=""

while (($# > 0)); do
  case "$1" in
    --disk)
      DISK="$2"
      shift 2
      ;;
    --hostname)
      HOSTNAME="$2"
      shift 2
      ;;
    --username)
      USERNAME="$2"
      shift 2
      ;;
    --timezone)
      TIMEZONE="$2"
      shift 2
      ;;
    --confirm-destroy)
      CONFIRM_DESTROY="$2"
      shift 2
      ;;
    --root-password-file)
      ROOT_PASSWORD_FILE="$2"
      shift 2
      ;;
    --user-password-file)
      USER_PASSWORD_FILE="$2"
      shift 2
      ;;
    --luks-password-file)
      LUKS_PASSWORD_FILE="$2"
      shift 2
      ;;
    --non-interactive)
      NON_INTERACTIVE=1
      shift
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

if [[ -n "$ROOT_PASSWORD_FILE" ]]; then
  ROOT_PASSWORD="$(<"$ROOT_PASSWORD_FILE")"
else
  ROOT_PASSWORD=""
fi

if [[ -n "$USER_PASSWORD_FILE" ]]; then
  USER_PASSWORD="$(<"$USER_PASSWORD_FILE")"
else
  USER_PASSWORD=""
fi

if [[ -n "$LUKS_PASSWORD_FILE" ]]; then
  LUKS_PASSPHRASE="$(<"$LUKS_PASSWORD_FILE")"
else
  LUKS_PASSPHRASE=""
fi

if [[ -z "$HOSTNAME" && "$NON_INTERACTIVE" -eq 0 ]]; then
  HOSTNAME="$(prompt_value 'Enter a hostname')"
fi

if [[ -z "$LUKS_PASSPHRASE" && "$NON_INTERACTIVE" -eq 0 ]]; then
  LUKS_PASSPHRASE="$(prompt_secret 'Enter a LUKS passphrase: ' 'Confirm your LUKS passphrase: ')"
fi

if [[ -z "$ROOT_PASSWORD" && "$NON_INTERACTIVE" -eq 0 ]]; then
  ROOT_PASSWORD="$(prompt_secret 'Enter a root password: ' 'Confirm your root password: ')"
fi

if [[ -z "$USER_PASSWORD" && "$NON_INTERACTIVE" -eq 0 ]]; then
  USER_PASSWORD="$(prompt_secret "Enter a password for user ${USERNAME}: " "Confirm password for user ${USERNAME}: ")"
fi

if [[ -z "$HOSTNAME" || -z "$LUKS_PASSPHRASE" || -z "$ROOT_PASSWORD" || -z "$USER_PASSWORD" ]]; then
  die "Missing required input. Provide flags/password files or run interactively."
fi

if [[ -z "$DISK" ]]; then
  mapfile -t DISKS < <(lsblk -d -n -o PATH | grep -E '^/dev/(sd|nvme|mmcblk|vd)')
  ((${#DISKS[@]} > 0)) || die "No install disks found"
  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    die "--disk is required in --non-interactive mode"
  fi
  DISK="$(printf '%s\n' "${DISKS[@]}" | gum choose --header='Select a disk to use for Arch Linux')"
fi

[[ -b "$DISK" ]] || die "Disk not found: $DISK"

if [[ "$CONFIRM_DESTROY" == "$DISK" ]]; then
  log "Destructive operation confirmed via --confirm-destroy"
else
  if [[ "$NON_INTERACTIVE" -eq 1 ]]; then
    die "Destructive operation requires --confirm-destroy $DISK"
  fi

  typed_confirmation="$(prompt_value "Type the disk path to confirm wipe ($DISK): ")"
  [[ "$typed_confirmation" == "$DISK" ]] || die "Disk confirmation did not match. Aborting."
fi

log "Syncing system clock"
timedatectl set-ntp true

BOOT_PARTITION="$(partition_path "$DISK" 1)"
LUKS_PARTITION="$(partition_path "$DISK" 2)"

log "Partitioning $DISK"
sgdisk --clear -n 1:0:+1G -t 1:ef00 -n 2:0:+0 -t 2:8e00 "$DISK"

[[ -b "$BOOT_PARTITION" ]] || die "Boot partition not found after partitioning: $BOOT_PARTITION"
[[ -b "$LUKS_PARTITION" ]] || die "LUKS partition not found after partitioning: $LUKS_PARTITION"

log "Formatting boot partition $BOOT_PARTITION"
mkfs.fat -F 32 "$BOOT_PARTITION"

log "Formatting LUKS partition $LUKS_PARTITION"
printf '%s' "$LUKS_PASSPHRASE" | cryptsetup luksFormat --batch-mode "$LUKS_PARTITION" --key-file -
printf '%s' "$LUKS_PASSPHRASE" | cryptsetup open "$LUKS_PARTITION" cryptlvm --key-file -

VG_NAME="vg1"
VG_ROOT_NAME="root"
VG_HOME_NAME="home"

log "Creating LVM volumes"
pvcreate /dev/mapper/cryptlvm
vgcreate "$VG_NAME" /dev/mapper/cryptlvm
lvcreate -L 80G "$VG_NAME" -n "$VG_ROOT_NAME"
lvcreate -l 100%FREE "$VG_NAME" -n "$VG_HOME_NAME"

VG_ROOT_PATH="/dev/${VG_NAME}/${VG_ROOT_NAME}"
VG_HOME_PATH="/dev/${VG_NAME}/${VG_HOME_NAME}"

log "Formatting logical volumes"
mkfs.ext4 -m 1 "$VG_ROOT_PATH"
mkfs.ext4 -m 1 "$VG_HOME_PATH"

log "Mounting target filesystem"
mount --mkdir "$VG_ROOT_PATH" /mnt
mount --mkdir "$VG_HOME_PATH" /mnt/home
mount --mkdir "$BOOT_PARTITION" /mnt/boot

"$SCRIPT_DIR/pacstrap.sh"

genfstab -U /mnt > /mnt/etc/fstab
sed -i 's/fmask=0022/fmask=0137/' /mnt/etc/fstab
sed -i 's/dmask=0022/dmask=0027/' /mnt/etc/fstab

TMP_CFG_DIR="$(mktemp -d)"

cat >"$TMP_CFG_DIR/95-systemd-boot.hook" <<'HOOK'
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Gracefully upgrading systemd-boot...
When = PostTransaction
Exec = /usr/bin/systemctl restart systemd-boot-update.service
HOOK

cat >"$TMP_CFG_DIR/hostonly.conf" <<'HOSTONLY'
hostonly="yes"
HOSTONLY

cat >"$TMP_CFG_DIR/uefi.conf" <<'UEFI'
uefi="yes"
UEFI

install -d -m 700 /mnt/root/cfgs /mnt/root/packages /mnt/root/secrets
cp -r "$SCRIPT_DIR/packages/." /mnt/root/packages/
cp "$TMP_CFG_DIR/95-systemd-boot.hook" /mnt/root/cfgs/95-systemd-boot.hook
cp "$TMP_CFG_DIR/hostonly.conf" /mnt/root/cfgs/hostonly.conf
cp "$TMP_CFG_DIR/uefi.conf" /mnt/root/cfgs/uefi.conf

install -m 700 "$SCRIPT_DIR/install-hooks.sh" /mnt/root/install-hooks.sh
install -m 700 "$SCRIPT_DIR/chrooted.sh" /mnt/root/chrooted.sh
install -m 700 "$SCRIPT_DIR/install-yay.sh" /mnt/root/install-yay.sh
install -m 700 "$SCRIPT_DIR/install-dotfiles.sh" /mnt/root/install-dotfiles.sh
install -m 700 "$SCRIPT_DIR/install-aur-packages.sh" /mnt/root/install-aur-packages.sh

umask 077
printf '%s' "$ROOT_PASSWORD" > /mnt/root/secrets/root_password
printf '%s' "$USER_PASSWORD" > /mnt/root/secrets/user_password
printf '%s' "$LUKS_PASSPHRASE" > /mnt/root/secrets/luks_passphrase

cat >/mnt/root/install-config.env <<CONFIG
HOSTNAME=${HOSTNAME}
USERNAME=${USERNAME}
TIMEZONE=${TIMEZONE}
LUKS_PARTITION=${LUKS_PARTITION}
ROOT_PASSWORD_FILE=/root/secrets/root_password
USER_PASSWORD_FILE=/root/secrets/user_password
LUKS_PASSWORD_FILE=/root/secrets/luks_passphrase
CONFIG
chmod 600 /mnt/root/install-config.env

(arch-chroot /mnt /root/install-hooks.sh) |& tee install-hooks.log
(arch-chroot /mnt /root/chrooted.sh /root/install-config.env) |& tee chrooted.log

log "Install completed"
