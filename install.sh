#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DISK=""
HOSTNAME=""
USERNAME="k"
TIMEZONE="America/Chicago"
CONFIRM_DESTROY=0
NON_INTERACTIVE=0
DRY_RUN=0
ROOT_PASSWORD_FILE=""
USER_PASSWORD_FILE=""
LUKS_PASSPHRASE_FILE=""

ROOT_PASSWORD=""
USER_PASSWORD=""
LUKS_PASSPHRASE=""

SECRETS_DIR="/mnt/root/.arch-installer-secrets"
CONFIG_FILE="/mnt/root/.arch-installer-config"

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --disk <path>                 Target disk (for example /dev/sda)
  --hostname <name>             Hostname for installed system
  --username <name>             Username (default: k)
  --timezone <tz>               Timezone (default: America/Chicago)
  --confirm-destroy             Skip typed disk-destroy confirmation prompt
  --root-password-file <path>   Read root password from file
  --user-password-file <path>   Read user password from file
  --luks-passphrase-file <path> Read LUKS passphrase from file
  --non-interactive             Fail instead of prompting for input
  --dry-run                     Print planned actions only
  --help                        Show this help text
EOF
}

log() {
    printf '[install] %s\n' "$*"
}

warn() {
    printf '[install] warning: %s\n' "$*" >&2
}

fatal() {
    printf '[install] error: %s\n' "$*" >&2
    exit 1
}

run() {
    if (( DRY_RUN )); then
        printf '[dry-run]'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    "$@"
}

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || fatal "Required command not found: $cmd"
}

ensure_gum_available() {
    if command -v gum >/dev/null 2>&1; then
        return 0
    fi

    log "gum not found; installing gum"
    run pacman -Sy --needed --noconfirm gum
    command -v gum >/dev/null 2>&1 || fatal "Failed to install gum"
}

read_secret_file() {
    local file_path="$1"
    [[ -r "$file_path" ]] || fatal "Secret file is not readable: $file_path"
    local value
    value="$(<"$file_path")"
    [[ -n "$value" ]] || fatal "Secret file is empty: $file_path"
    printf '%s' "$value"
}

read_secret_prompt() {
    local label="$1"
    local first second
    while true; do
        first="$(gum input --password --placeholder "Enter ${label}: ")"
        second="$(gum input --password --placeholder "Confirm ${label}: ")"
        if [[ "$first" == "$second" ]]; then
            printf '%s' "$first"
            return 0
        fi
        warn "Values are not equal for ${label}"
    done
}

prompt_input() {
    local prompt="$1"
    local value
    value="$(gum input --placeholder "$prompt")"
    printf '%s' "$value"
}

partition_path() {
    local disk="$1"
    local index="$2"
    if [[ "$disk" =~ (nvme[0-9]+n[0-9]+|mmcblk[0-9]+|loop[0-9]+)$ ]]; then
        printf '%sp%s' "$disk" "$index"
    else
        printf '%s%s' "$disk" "$index"
    fi
}

ensure_disk_partitions_unmounted() {
    local disk="$1"
    local part

    mapfile -t disk_parts < <(lsblk -lnpo NAME,TYPE "$disk" | awk '$2 == "part" { print $1 }')
    if [[ ${#disk_parts[@]} -eq 0 ]]; then
        return 0
    fi

    for part in "${disk_parts[@]}"; do
        if findmnt -rn "$part" >/dev/null 2>&1; then
            log "Unmounting ${part} before formatting"
            run umount -R "$part"
        fi

        if swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq "$part"; then
            log "Disabling swap on ${part} before formatting"
            run swapoff "$part"
        fi
    done

    for part in "${disk_parts[@]}"; do
        if findmnt -rn "$part" >/dev/null 2>&1; then
            fatal "Partition is still mounted: ${part}"
        fi

        if swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq "$part"; then
            fatal "Partition is still active swap: ${part}"
        fi
    done
}

cleanup_sensitive_files() {
    if (( DRY_RUN )); then
        return
    fi
    rm -f "$CONFIG_FILE" || true
    rm -f "$SECRETS_DIR/root_password" "$SECRETS_DIR/user_password" "$SECRETS_DIR/luks_passphrase" || true
    rmdir "$SECRETS_DIR" 2>/dev/null || true
}

trap cleanup_sensitive_files EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk)
            DISK="${2:-}"
            shift 2
            ;;
        --hostname)
            HOSTNAME="${2:-}"
            shift 2
            ;;
        --username)
            USERNAME="${2:-}"
            shift 2
            ;;
        --timezone)
            TIMEZONE="${2:-}"
            shift 2
            ;;
        --confirm-destroy)
            CONFIRM_DESTROY=1
            shift
            ;;
        --root-password-file)
            ROOT_PASSWORD_FILE="${2:-}"
            shift 2
            ;;
        --user-password-file)
            USER_PASSWORD_FILE="${2:-}"
            shift 2
            ;;
        --luks-passphrase-file)
            LUKS_PASSPHRASE_FILE="${2:-}"
            shift 2
            ;;
        --non-interactive)
            NON_INTERACTIVE=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            fatal "Unknown option: $1"
            ;;
    esac
done

require_cmd lsblk
require_cmd sgdisk
require_cmd cryptsetup
require_cmd pvcreate
require_cmd vgcreate
require_cmd lvcreate
require_cmd mkfs.fat
require_cmd mkfs.ext4
require_cmd mount
require_cmd partprobe
require_cmd findmnt
require_cmd umount
require_cmd swapon
require_cmd swapoff
require_cmd arch-chroot
require_cmd genfstab
require_cmd pacman

if (( NON_INTERACTIVE == 0 )); then
    ensure_gum_available
fi

if [[ -z "$DISK" ]]; then
    if (( NON_INTERACTIVE )); then
        fatal "--disk is required in --non-interactive mode"
    fi

    mapfile -t disks < <(lsblk -dpno NAME,TYPE | awk '$2 == "disk" { print $1 }')
    [[ ${#disks[@]} -gt 0 ]] || fatal "No disks detected"
    DISK="$(printf '%s\n' "${disks[@]}" | gum choose --header "Select a disk to use for Arch Linux")"
fi

[[ -b "$DISK" ]] || fatal "Disk path is not a block device: $DISK"

if [[ -z "$HOSTNAME" ]]; then
    if (( NON_INTERACTIVE )); then
        fatal "--hostname is required in --non-interactive mode"
    fi
    HOSTNAME="$(prompt_input "Enter a hostname")"
fi
[[ -n "$HOSTNAME" ]] || fatal "Hostname cannot be empty"

if (( NON_INTERACTIVE )) && (( CONFIRM_DESTROY == 0 )); then
    fatal "--confirm-destroy is required in --non-interactive mode"
fi

if (( CONFIRM_DESTROY == 0 )); then
    typed_disk="$(gum input --prompt "Type ${DISK} to confirm disk wipe: ")"
    [[ "$typed_disk" == "$DISK" ]] || fatal "Confirmation text mismatch. Refusing to wipe disk"
fi

if (( DRY_RUN == 0 )); then
    run timedatectl set-ntp true

    if [[ -n "$LUKS_PASSPHRASE_FILE" ]]; then
        LUKS_PASSPHRASE="$(read_secret_file "$LUKS_PASSPHRASE_FILE")"
    elif (( NON_INTERACTIVE )); then
        fatal "--luks-passphrase-file is required in --non-interactive mode"
    else
        LUKS_PASSPHRASE="$(read_secret_prompt "a LUKS passphrase")"
    fi

    if [[ -n "$ROOT_PASSWORD_FILE" ]]; then
        ROOT_PASSWORD="$(read_secret_file "$ROOT_PASSWORD_FILE")"
    elif (( NON_INTERACTIVE )); then
        fatal "--root-password-file is required in --non-interactive mode"
    else
        ROOT_PASSWORD="$(read_secret_prompt "a root password")"
    fi

    if [[ -n "$USER_PASSWORD_FILE" ]]; then
        USER_PASSWORD="$(read_secret_file "$USER_PASSWORD_FILE")"
    elif (( NON_INTERACTIVE )); then
        fatal "--user-password-file is required in --non-interactive mode"
    else
        USER_PASSWORD="$(read_secret_prompt "a user password")"
    fi
fi

BOOT_PARTITION="$(partition_path "$DISK" 1)"
LUKS_PARTITION="$(partition_path "$DISK" 2)"

if (( DRY_RUN )); then
    log "Planned actions:"
    log "- wipe and partition ${DISK}"
    log "- boot partition: ${BOOT_PARTITION}"
    log "- luks partition: ${LUKS_PARTITION}"
    log "- install user: ${USERNAME}"
    log "- timezone: ${TIMEZONE}"
    log "- hostname: ${HOSTNAME}"
    exit 0
fi

log "Partitioning disk ${DISK}"
ensure_disk_partitions_unmounted "$DISK"
run sgdisk --clear -n 1:0:+1G -t 1:ef00 -n 2:0:+0 -t 2:8e00 "$DISK"
run partprobe "$DISK"

[[ -b "$BOOT_PARTITION" ]] || fatal "Boot partition not found: $BOOT_PARTITION"
[[ -b "$LUKS_PARTITION" ]] || fatal "LUKS partition not found: $LUKS_PARTITION"

log "Formatting boot partition ${BOOT_PARTITION}"
run mkfs.fat -F 32 "$BOOT_PARTITION"

log "Formatting and opening LUKS partition ${LUKS_PARTITION}"
printf '%s' "$LUKS_PASSPHRASE" | cryptsetup luksFormat "$LUKS_PARTITION" -
printf '%s' "$LUKS_PASSPHRASE" | cryptsetup open "$LUKS_PARTITION" cryptlvm --key-file -

VG_NAME="vg1"
VG_ROOT_NAME="root"
VG_ROOT_PATH="/dev/${VG_NAME}/${VG_ROOT_NAME}"

run pvcreate /dev/mapper/cryptlvm
run vgcreate "$VG_NAME" /dev/mapper/cryptlvm
run lvcreate -l 100%FREE "$VG_NAME" -n "$VG_ROOT_NAME"

run mkfs.ext4 -m 1 "$VG_ROOT_PATH"

run mount --mkdir "$VG_ROOT_PATH" /mnt
run mount --mkdir "$BOOT_PARTITION" /mnt/boot

"${SCRIPT_DIR}/pacstrap.sh"

genfstab -U /mnt >> /mnt/etc/fstab
sed -i 's/fmask=0022/fmask=0137/' /mnt/etc/fstab
sed -i 's/dmask=0022/dmask=0027/' /mnt/etc/fstab

mkdir -p "${SCRIPT_DIR}/cfgs"
cat <<'EOF' >"${SCRIPT_DIR}/cfgs/95-systemd-boot.hook"
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Gracefully upgrading systemd-boot...
When = PostTransaction
Exec = /usr/bin/systemctl restart systemd-boot-update.service
EOF

cat <<'EOF' >"${SCRIPT_DIR}/cfgs/hostonly.conf"
hostonly="yes"
EOF

cat <<'EOF' >"${SCRIPT_DIR}/cfgs/uefi.conf"
uefi="yes"
EOF

install -d -m 700 "$SECRETS_DIR"
printf '%s' "$ROOT_PASSWORD" >"$SECRETS_DIR/root_password"
printf '%s' "$USER_PASSWORD" >"$SECRETS_DIR/user_password"
printf '%s' "$LUKS_PASSPHRASE" >"$SECRETS_DIR/luks_passphrase"
chmod 600 "$SECRETS_DIR/root_password" "$SECRETS_DIR/user_password" "$SECRETS_DIR/luks_passphrase"

cat <<EOF >"$CONFIG_FILE"
HOSTNAME=$(printf '%q' "$HOSTNAME")
USERNAME=$(printf '%q' "$USERNAME")
TIMEZONE=$(printf '%q' "$TIMEZONE")
LUKS_PARTITION=$(printf '%q' "$LUKS_PARTITION")
EOF
chmod 600 "$CONFIG_FILE"

cp -r "${SCRIPT_DIR}/cfgs" /mnt/root/cfgs
cp -r "${SCRIPT_DIR}/packages" /mnt/root/packages
install -m 0755 "${SCRIPT_DIR}/install-hooks.sh" /mnt/root/install-hooks.sh
install -m 0755 "${SCRIPT_DIR}/chrooted.sh" /mnt/root/chrooted.sh
install -m 0755 "${SCRIPT_DIR}/install-yay.sh" /mnt/root/install-yay.sh
install -m 0755 "${SCRIPT_DIR}/install-dotfiles.sh" /mnt/root/install-dotfiles.sh
install -m 0755 "${SCRIPT_DIR}/install-aur-packages.sh" /mnt/root/install-aur-packages.sh

( arch-chroot /mnt /root/install-hooks.sh ) |& tee install-hooks.log
( arch-chroot /mnt /root/chrooted.sh --config /root/.arch-installer-config --secrets-dir /root/.arch-installer-secrets ) |& tee chrooted.log

log "Install flow completed"
