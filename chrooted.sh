#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'
umask 077

CONFIG_FILE=""
SECRETS_DIR=""

HOSTNAME=""
USERNAME=""
TIMEZONE=""
LUKS_PARTITION=""

ROOT_PASSWORD=""
USER_PASSWORD=""
LUKS_PASSPHRASE=""

WHEEL_BACKUP=""
SUDOERS_MODIFIED=0
LUKS_KEY_FILE=""

usage() {
    cat <<'EOF'
Usage: /root/chrooted.sh --config <path> --secrets-dir <path>
EOF
}

log() {
    printf '[chroot] %s\n' "$*"
}

fatal() {
    printf '[chroot] error: %s\n' "$*" >&2
    exit 1
}

require_cmd() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || fatal "Required command not found: $cmd"
}

cleanup() {
    if (( SUDOERS_MODIFIED )); then
        if [[ -n "$WHEEL_BACKUP" && -f "$WHEEL_BACKUP" ]]; then
            mv -f "$WHEEL_BACKUP" /etc/sudoers.d/wheel
        else
            rm -f /etc/sudoers.d/wheel
        fi
        SUDOERS_MODIFIED=0
    fi

    if [[ -n "$LUKS_KEY_FILE" && -f "$LUKS_KEY_FILE" ]]; then
        rm -f "$LUKS_KEY_FILE"
    fi

    if [[ -n "$SECRETS_DIR" && -d "$SECRETS_DIR" ]]; then
        rm -f "$SECRETS_DIR/root_password" "$SECRETS_DIR/user_password" "$SECRETS_DIR/luks_passphrase" || true
        rmdir "$SECRETS_DIR" 2>/dev/null || true
    fi

    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"
    fi
}

trap cleanup EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            CONFIG_FILE="${2:-}"
            shift 2
            ;;
        --secrets-dir)
            SECRETS_DIR="${2:-}"
            shift 2
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

[[ -n "$CONFIG_FILE" ]] || fatal "--config is required"
[[ -n "$SECRETS_DIR" ]] || fatal "--secrets-dir is required"
[[ -f "$CONFIG_FILE" ]] || fatal "Config file not found: $CONFIG_FILE"
[[ -d "$SECRETS_DIR" ]] || fatal "Secrets dir not found: $SECRETS_DIR"

# shellcheck disable=SC1090
source "$CONFIG_FILE"

[[ -n "$HOSTNAME" ]] || fatal "HOSTNAME missing from config"
[[ -n "$USERNAME" ]] || fatal "USERNAME missing from config"
[[ -n "$TIMEZONE" ]] || fatal "TIMEZONE missing from config"
[[ -n "$LUKS_PARTITION" ]] || fatal "LUKS_PARTITION missing from config"

ROOT_PASSWORD="$(<"$SECRETS_DIR/root_password")"
USER_PASSWORD="$(<"$SECRETS_DIR/user_password")"
LUKS_PASSPHRASE="$(<"$SECRETS_DIR/luks_passphrase")"

[[ -n "$ROOT_PASSWORD" ]] || fatal "root password is empty"
[[ -n "$USER_PASSWORD" ]] || fatal "user password is empty"

require_cmd pacman
require_cmd chpasswd
require_cmd useradd
require_cmd usermod
require_cmd systemctl

log "Setting timezone to ${TIMEZONE}"
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

log "Generating locale"
sed -i -e 's|#en_US.UTF-8 UTF-8|en_US.UTF-8 UTF-8|' /etc/locale.gen
locale-gen
printf 'LANG=en_US.UTF-8\n' >/etc/locale.conf

log "Installing graphical environment packages"
pacman -S --needed --noconfirm - < /root/packages/wm.txt

log "Configuring root password"
printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd

if id -u "$USERNAME" >/dev/null 2>&1; then
    log "User ${USERNAME} already exists, skipping creation"
else
    log "Creating user ${USERNAME}"
    useradd -m "$USERNAME"
fi

log "Configuring password for ${USERNAME}"
printf '%s:%s\n' "$USERNAME" "$USER_PASSWORD" | chpasswd
usermod -aG wheel "$USERNAME"

if [[ -f /etc/sudoers.d/wheel ]]; then
    WHEEL_BACKUP="$(mktemp /etc/sudoers.d/wheel.backup.XXXXXX)"
    cp /etc/sudoers.d/wheel "$WHEEL_BACKUP"
fi
printf '%%wheel ALL=(ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel
SUDOERS_MODIFIED=1

if command -v zsh >/dev/null 2>&1; then
    chsh -s "$(command -v zsh)" "$USERNAME"
fi

install -m 0755 /root/install-yay.sh "/home/${USERNAME}/install-yay.sh"
install -m 0755 /root/install-dotfiles.sh "/home/${USERNAME}/install-dotfiles.sh"
install -m 0755 /root/install-aur-packages.sh "/home/${USERNAME}/install-aur-packages.sh"
install -m 0644 /root/packages/aur.txt "/home/${USERNAME}/aur.txt"
chown "$USERNAME":"$USERNAME" "/home/${USERNAME}/install-yay.sh"
chown "$USERNAME":"$USERNAME" "/home/${USERNAME}/install-dotfiles.sh"
chown "$USERNAME":"$USERNAME" "/home/${USERNAME}/install-aur-packages.sh"
chown "$USERNAME":"$USERNAME" "/home/${USERNAME}/aur.txt"

su - "$USERNAME" -c "/home/${USERNAME}/install-yay.sh"
su - "$USERNAME" -c "/home/${USERNAME}/install-aur-packages.sh"
su - "$USERNAME" -c "/home/${USERNAME}/install-dotfiles.sh"

if [[ -n "$WHEEL_BACKUP" && -f "$WHEEL_BACKUP" ]]; then
    mv -f "$WHEEL_BACKUP" /etc/sudoers.d/wheel
else
    printf '%%wheel ALL=(ALL:ALL) ALL\n' >/etc/sudoers.d/wheel
    chmod 440 /etc/sudoers.d/wheel
fi
SUDOERS_MODIFIED=0

printf '%s\n' "$HOSTNAME" >/etc/hostname

log "Installing systemd-boot"
bootctl install

if [[ -n "$LUKS_PASSPHRASE" && -b "$LUKS_PARTITION" ]]; then
    log "Enrolling TPM2 unlock key"
    LUKS_KEY_FILE="$(mktemp /run/luks-key.XXXXXX)"
    chmod 600 "$LUKS_KEY_FILE"
    printf '%s' "$LUKS_PASSPHRASE" >"$LUKS_KEY_FILE"
    systemd-cryptenroll --wipe-slot tpm2 --tpm2-device auto --unlock-key-file="$LUKS_KEY_FILE" "$LUKS_PARTITION"
    rm -f "$LUKS_KEY_FILE"
    LUKS_KEY_FILE=""
else
    log "Skipping TPM2 enrollment; missing LUKS passphrase or partition"
fi

ln -sf /dev/null /etc/pacman.d/hooks/90-dracut-install.hook
dracut --regenerate-all

ROOT_SOURCE="$(findmnt / -n -o SOURCE)"
ROOT_FSTYPE="$(findmnt / -n -o FSTYPE)"
LVM_PAIR="$(lvs --noheadings -o vg_name,lv_name --separator '/' "$ROOT_SOURCE" | tr -d ' ')"

if [[ -z "$LVM_PAIR" ]]; then
    fatal "Could not detect root LVM pair"
fi

VG_NAME="${LVM_PAIR%/*}"
LV_NAME="${LVM_PAIR#*/}"

LUKS_UUID="$(blkid -s UUID -o value "$LUKS_PARTITION" || true)"
LUKS_ARG=""
if [[ -n "$LUKS_UUID" ]]; then
    LUKS_ARG="rd.luks.uuid=${LUKS_UUID}"
fi

CMDLINE="${LUKS_ARG} rd.lvm.lv=${VG_NAME}/${LV_NAME} root=/dev/mapper/${VG_NAME}-${LV_NAME} rootfstype=${ROOT_FSTYPE} rootflags=rw,relatime"
mkdir -p /etc/kernel
printf '%s\n' "$CMDLINE" >/etc/kernel/cmdline

log "Generated kernel cmdline: ${CMDLINE}"

systemctl enable NetworkManager
log "Chroot configuration completed"
