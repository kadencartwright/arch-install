#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/install-nixos.sh [options]

Options:
  --disk PATH                Target disk
  --confirm-destroy PATH     Must exactly match --disk
  --hostname NAME            Hostname
  --username NAME            Username (default: k)
  --timezone TZ              Timezone (default: America/Chicago)
  --root-password-file PATH  Root password plaintext file
  --user-password-file PATH  User password plaintext file
  --luks-password-file PATH  LUKS passphrase file
  --repo-url URL             Git repo URL for /etc/nixos
  --repo-ref REF             Git branch/tag/commit (default: main)
  --reboot                   Reboot automatically after install
  --non-interactive          Fail instead of prompting for missing inputs
  --help                     Show help

If values are omitted, the script prompts interactively using gum.
USAGE
}

log() {
  printf '[install-nixos] %s\n' "$*"
}

die() {
  printf '[install-nixos] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

partition_path() {
  local disk="$1"
  local idx="$2"
  if [[ "$disk" =~ ^/dev/(nvme|mmcblk) ]]; then
    printf '%sp%s' "$disk" "$idx"
  else
    printf '%s%s' "$disk" "$idx"
  fi
}

hash_password() {
  local plaintext="$1"
  if have_cmd mkpasswd; then
    mkpasswd -m sha-512 "$plaintext"
    return
  fi
  if have_cmd openssl; then
    openssl passwd -6 "$plaintext"
    return
  fi
  die "Need mkpasswd (whois) or openssl to hash passwords"
}

ensure_gum() {
  if have_cmd gum; then
    return
  fi

  log "gum not found; attempting to install"

  if have_cmd nix; then
    nix --extra-experimental-features "nix-command flakes" profile install nixpkgs#gum >/dev/null 2>&1 || true
  fi

  if ! have_cmd gum && have_cmd nix-env; then
    nix-env -iA nixos.gum >/dev/null 2>&1 || true
  fi

  if have_cmd gum; then
    log "gum installed successfully"
    return
  fi

  log "gum install failed; falling back to basic prompts"
}

prompt_input() {
  local label="$1"
  local default_value="${2:-}"
  local value=""

  if have_cmd gum; then
    if [[ -n "$default_value" ]]; then
      value="$(gum input --prompt "${label}: " --value "$default_value")"
    else
      value="$(gum input --prompt "${label}: ")"
    fi
  else
    if [[ -n "$default_value" ]]; then
      read -r -p "${label} [${default_value}]: " value
      value="${value:-$default_value}"
    else
      read -r -p "${label}: " value
    fi
  fi

  [[ -n "$value" ]] || die "${label} is required"
  printf '%s' "$value"
}

prompt_password() {
  local label="$1"
  local first=""
  local second=""

  while true; do
    if have_cmd gum; then
      first="$(gum input --password --prompt "${label}: ")"
      second="$(gum input --password --prompt "Confirm ${label}: ")"
    else
      read -r -s -p "${label}: " first
      printf '\n'
      read -r -s -p "Confirm ${label}: " second
      printf '\n'
    fi

    if [[ -n "$first" && "$first" == "$second" ]]; then
      printf '%s' "$first"
      return
    fi

    log "Values did not match. Try again."
  done
}

prompt_confirm_destroy() {
  local disk="$1"

  if have_cmd gum; then
    gum confirm "This will ERASE ${disk}. Continue?" || die "Cancelled"
    local typed
    typed="$(gum input --prompt "Type disk path to confirm wipe: " --placeholder "$disk")"
    [[ "$typed" == "$disk" ]] || die "Disk confirmation mismatch"
  else
    local yn
    read -r -p "This will ERASE ${disk}. Continue? [y/N]: " yn
    [[ "$yn" =~ ^[Yy]$ ]] || die "Cancelled"
    local typed
    read -r -p "Type disk path to confirm wipe (${disk}): " typed
    [[ "$typed" == "$disk" ]] || die "Disk confirmation mismatch"
  fi
}

choose_disk() {
  mapfile -t disks < <(lsblk -d -n -o PATH | grep -E '^/dev/(sd|nvme|mmcblk|vd)')
  ((${#disks[@]} > 0)) || die "No install disks found"

  if have_cmd gum; then
    printf '%s\n' "${disks[@]}" | gum choose --header "Select install disk"
  else
    printf 'Available disks:\n'
    printf '  %s\n' "${disks[@]}"
    read -r -p "Enter target disk path: " disk
    [[ -n "$disk" ]] || die "Disk is required"
    printf '%s' "$disk"
  fi
}

DISK=""
CONFIRM_DESTROY=""
HOSTNAME=""
USERNAME="k"
TIMEZONE="America/Chicago"
ROOT_PASSWORD_FILE=""
USER_PASSWORD_FILE=""
LUKS_PASSWORD_FILE=""
REPO_URL=""
REPO_REF="main"
DO_REBOOT=0
REBOOT_SET=0
NON_INTERACTIVE=0

while (($# > 0)); do
  case "$1" in
    --disk)
      DISK="${2:-}"; shift 2 ;;
    --confirm-destroy)
      CONFIRM_DESTROY="${2:-}"; shift 2 ;;
    --hostname)
      HOSTNAME="${2:-}"; shift 2 ;;
    --username)
      USERNAME="${2:-}"; shift 2 ;;
    --timezone)
      TIMEZONE="${2:-}"; shift 2 ;;
    --root-password-file)
      ROOT_PASSWORD_FILE="${2:-}"; shift 2 ;;
    --user-password-file)
      USER_PASSWORD_FILE="${2:-}"; shift 2 ;;
    --luks-password-file)
      LUKS_PASSWORD_FILE="${2:-}"; shift 2 ;;
    --repo-url)
      REPO_URL="${2:-}"; shift 2 ;;
    --repo-ref)
      REPO_REF="${2:-}"; shift 2 ;;
    --reboot)
      DO_REBOOT=1; REBOOT_SET=1; shift ;;
    --non-interactive)
      NON_INTERACTIVE=1; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      die "Unknown argument: $1" ;;
  esac
done

[[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run as root from installer ISO"

require_cmd lsblk
ensure_gum

if [[ -z "$DISK" ]]; then
  [[ "$NON_INTERACTIVE" -eq 0 ]] || die "--disk is required in --non-interactive mode"
  DISK="$(choose_disk)"
fi
[[ -b "$DISK" ]] || die "Disk not found: $DISK"

if [[ -z "$HOSTNAME" ]]; then
  [[ "$NON_INTERACTIVE" -eq 0 ]] || die "--hostname is required in --non-interactive mode"
  HOSTNAME="$(prompt_input "Hostname")"
fi

if [[ "$NON_INTERACTIVE" -eq 0 ]]; then
  USERNAME="$(prompt_input "Username" "$USERNAME")"
  TIMEZONE="$(prompt_input "Timezone" "$TIMEZONE")"
fi

if [[ -n "$CONFIRM_DESTROY" ]]; then
  [[ "$CONFIRM_DESTROY" == "$DISK" ]] || die "--confirm-destroy must match --disk"
else
  [[ "$NON_INTERACTIVE" -eq 0 ]] || die "--confirm-destroy is required in --non-interactive mode"
  prompt_confirm_destroy "$DISK"
fi

ROOT_PASSWORD=""
USER_PASSWORD=""
LUKS_PASSWORD=""

if [[ -n "$ROOT_PASSWORD_FILE" ]]; then
  [[ -f "$ROOT_PASSWORD_FILE" ]] || die "Root password file not found"
  ROOT_PASSWORD="$(<"$ROOT_PASSWORD_FILE")"
else
  [[ "$NON_INTERACTIVE" -eq 0 ]] || die "--root-password-file is required in --non-interactive mode"
  ROOT_PASSWORD="$(prompt_password "Root password")"
fi

if [[ -n "$USER_PASSWORD_FILE" ]]; then
  [[ -f "$USER_PASSWORD_FILE" ]] || die "User password file not found"
  USER_PASSWORD="$(<"$USER_PASSWORD_FILE")"
else
  [[ "$NON_INTERACTIVE" -eq 0 ]] || die "--user-password-file is required in --non-interactive mode"
  USER_PASSWORD="$(prompt_password "User password (${USERNAME})")"
fi

if [[ -n "$LUKS_PASSWORD_FILE" ]]; then
  [[ -f "$LUKS_PASSWORD_FILE" ]] || die "LUKS password file not found"
  LUKS_PASSWORD="$(<"$LUKS_PASSWORD_FILE")"
else
  [[ "$NON_INTERACTIVE" -eq 0 ]] || die "--luks-password-file is required in --non-interactive mode"
  LUKS_PASSWORD="$(prompt_password "LUKS passphrase")"
fi

[[ -n "$ROOT_PASSWORD" ]] || die "Root password is empty"
[[ -n "$USER_PASSWORD" ]] || die "User password is empty"
[[ -n "$LUKS_PASSWORD" ]] || die "LUKS passphrase is empty"

if [[ -z "$REPO_URL" ]]; then
  if [[ "$NON_INTERACTIVE" -eq 0 ]] && have_cmd gum; then
    repo_mode="$(printf '%s\n' "Use local checkout" "Clone from git URL" | gum choose --header "NixOS config source")"
    if [[ "$repo_mode" == "Clone from git URL" ]]; then
      REPO_URL="$(prompt_input "Repo URL")"
      REPO_REF="$(prompt_input "Repo ref" "$REPO_REF")"
    fi
  fi
fi

if [[ "$NON_INTERACTIVE" -eq 0 ]] && [[ "$REBOOT_SET" -eq 0 ]] && have_cmd gum; then
  if gum confirm "Reboot automatically after installation?"; then
    DO_REBOOT=1
  else
    DO_REBOOT=0
  fi
fi

require_cmd sgdisk
require_cmd cryptsetup
require_cmd pvcreate
require_cmd vgcreate
require_cmd lvcreate
require_cmd mkfs.fat
require_cmd mkfs.ext4
require_cmd mount
require_cmd nixos-generate-config
require_cmd nixos-install
require_cmd sed
require_cmd cp

ROOT_HASH="$(hash_password "$ROOT_PASSWORD")"
USER_HASH="$(hash_password "$USER_PASSWORD")"

BOOT_PARTITION="$(partition_path "$DISK" 1)"
LUKS_PARTITION="$(partition_path "$DISK" 2)"

log "Partitioning ${DISK}"
sgdisk --zap-all "$DISK"
sgdisk --clear -n 1:0:+1G -t 1:ef00 -n 2:0:+0 -t 2:8309 "$DISK"
udevadm settle

[[ -b "$BOOT_PARTITION" ]] || die "Boot partition missing: $BOOT_PARTITION"
[[ -b "$LUKS_PARTITION" ]] || die "LUKS partition missing: $LUKS_PARTITION"

log "Formatting EFI partition"
mkfs.fat -F 32 "$BOOT_PARTITION"

log "Setting up LUKS"
printf '%s' "$LUKS_PASSWORD" | cryptsetup luksFormat --batch-mode "$LUKS_PARTITION" --key-file -
printf '%s' "$LUKS_PASSWORD" | cryptsetup open "$LUKS_PARTITION" cryptlvm --key-file -

log "Creating LVM layout"
pvcreate /dev/mapper/cryptlvm
vgcreate vg1 /dev/mapper/cryptlvm
lvcreate -L 80G vg1 -n root
lvcreate -l 100%FREE vg1 -n home

log "Formatting filesystems"
mkfs.ext4 -m 1 /dev/vg1/root
mkfs.ext4 -m 1 /dev/vg1/home

log "Mounting target"
mount /dev/vg1/root /mnt
mkdir -p /mnt/home /mnt/boot
mount /dev/vg1/home /mnt/home
mount "$BOOT_PARTITION" /mnt/boot

log "Generating hardware config"
nixos-generate-config --root /mnt

HW_TMP="$(mktemp /tmp/hardware-config.XXXXXX)"
cp /mnt/etc/nixos/hardware-configuration.nix "$HW_TMP"

if [[ -n "$REPO_URL" ]]; then
  require_cmd git
  log "Cloning repo into /mnt/etc/nixos"
  rm -rf /mnt/etc/nixos
  git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" /mnt/etc/nixos
else
  log "Copying current repo into /mnt/etc/nixos"
  rm -rf /mnt/etc/nixos
  mkdir -p /mnt/etc/nixos
  cp -a "$REPO_ROOT"/. /mnt/etc/nixos/
fi

cp "$HW_TMP" /mnt/etc/nixos/hardware-configuration.nix

[[ -f /mnt/etc/nixos/nixos/configuration.nix.template ]] || die "Missing nixos/configuration.nix.template in repo"
cp /mnt/etc/nixos/nixos/configuration.nix.template /mnt/etc/nixos/configuration.nix

sed -i "s|__HOSTNAME__|${HOSTNAME}|g" /mnt/etc/nixos/configuration.nix
sed -i "s|__USERNAME__|${USERNAME}|g" /mnt/etc/nixos/configuration.nix
sed -i "s|__TIMEZONE__|${TIMEZONE}|g" /mnt/etc/nixos/configuration.nix
sed -i "s|__ROOT_HASH__|${ROOT_HASH}|g" /mnt/etc/nixos/configuration.nix
sed -i "s|__USER_HASH__|${USER_HASH}|g" /mnt/etc/nixos/configuration.nix

mkdir -p /mnt/var/lib/install
printf '%s' "$LUKS_PARTITION" > /mnt/var/lib/install/luks-partition
printf '%s' "$LUKS_PASSWORD" > /mnt/var/lib/install/luks-passphrase
chmod 600 /mnt/var/lib/install/luks-partition /mnt/var/lib/install/luks-passphrase

log "Installing NixOS"
nixos-install --root /mnt --no-root-passwd

log "Installation complete"
if [[ "$DO_REBOOT" -eq 1 ]]; then
  log "Rebooting"
  reboot
else
  log "Run 'reboot' when ready"
fi
