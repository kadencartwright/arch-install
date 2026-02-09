#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

log() {
  printf '[chrooted] %s\n' "$*"
}

die() {
  printf '[chrooted] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

ensure_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run this script as root"
}

CONFIG_FILE="${1:-/root/install-config.env}"
[[ -f "$CONFIG_FILE" ]] || die "Config file not found: $CONFIG_FILE"

# shellcheck disable=SC1090
source "$CONFIG_FILE"

: "${HOSTNAME:?HOSTNAME is required}"
: "${USERNAME:?USERNAME is required}"
: "${TIMEZONE:?TIMEZONE is required}"
: "${LUKS_PARTITION:?LUKS_PARTITION is required}"
: "${ROOT_PASSWORD_FILE:?ROOT_PASSWORD_FILE is required}"
: "${USER_PASSWORD_FILE:?USER_PASSWORD_FILE is required}"
: "${LUKS_PASSWORD_FILE:?LUKS_PASSWORD_FILE is required}"

[[ -f "$ROOT_PASSWORD_FILE" ]] || die "Missing root password file"
[[ -f "$USER_PASSWORD_FILE" ]] || die "Missing user password file"
[[ -f "$LUKS_PASSWORD_FILE" ]] || die "Missing LUKS password file"

ROOT_PASSWORD="$(<"$ROOT_PASSWORD_FILE")"
USER_PASSWORD="$(<"$USER_PASSWORD_FILE")"
LUKS_PASSPHRASE="$(<"$LUKS_PASSWORD_FILE")"

restore_sudoers() {
  if [[ -f /etc/sudoers.d/wheel.install-backup ]]; then
    mv -f /etc/sudoers.d/wheel.install-backup /etc/sudoers.d/wheel
  else
    printf '%%wheel ALL=(ALL:ALL) ALL\n' >/etc/sudoers.d/wheel
  fi
  chmod 440 /etc/sudoers.d/wheel
}

cleanup() {
  rm -f "$ROOT_PASSWORD_FILE" "$USER_PASSWORD_FILE" "$LUKS_PASSWORD_FILE"
  rm -f "$CONFIG_FILE"
  restore_sudoers
}
trap cleanup EXIT

ensure_root
require_cmd pacman
require_cmd useradd
require_cmd chpasswd
require_cmd usermod
require_cmd chsh
require_cmd bootctl
require_cmd dracut
require_cmd findmnt
require_cmd lvs
require_cmd blkid
require_cmd systemctl

log "Setting timezone to $TIMEZONE"
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

log "Installing packages"
pacman -S --noconfirm --needed - < /root/packages/wm.txt

sed -i -e 's|#en_US.UTF-8 UTF-8|en_US.UTF-8 UTF-8|' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >/etc/locale.conf

log "Setting root password"
printf 'root:%s\n' "$ROOT_PASSWORD" | chpasswd

if id -u "$USERNAME" >/dev/null 2>&1; then
  log "User $USERNAME already exists"
else
  log "Creating user: $USERNAME"
  useradd -m "$USERNAME"
fi

log "Setting password for user: $USERNAME"
printf '%s:%s\n' "$USERNAME" "$USER_PASSWORD" | chpasswd
usermod -aG wheel "$USERNAME"

if [[ -f /etc/sudoers.d/wheel ]]; then
  cp /etc/sudoers.d/wheel /etc/sudoers.d/wheel.install-backup
fi
printf '%%wheel ALL=(ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

if command -v zsh >/dev/null 2>&1; then
  chsh -s "$(command -v zsh)" "$USERNAME"
fi

install -m 700 /root/install-yay.sh "/home/${USERNAME}/install-yay.sh"
install -m 700 /root/install-dotfiles.sh "/home/${USERNAME}/install-dotfiles.sh"
install -m 700 /root/install-aur-packages.sh "/home/${USERNAME}/install-aur-packages.sh"
install -m 600 /root/packages/aur.txt "/home/${USERNAME}/aur.txt"
chown "$USERNAME:$USERNAME" "/home/${USERNAME}/install-yay.sh"
chown "$USERNAME:$USERNAME" "/home/${USERNAME}/install-dotfiles.sh"
chown "$USERNAME:$USERNAME" "/home/${USERNAME}/install-aur-packages.sh"
chown "$USERNAME:$USERNAME" "/home/${USERNAME}/aur.txt"

su - "$USERNAME" -c "/home/${USERNAME}/install-yay.sh"
su - "$USERNAME" -c "/home/${USERNAME}/install-aur-packages.sh"
su - "$USERNAME" -c "/home/${USERNAME}/install-dotfiles.sh"

printf '%s\n' "$HOSTNAME" >/etc/hostname

log "Installing systemd-boot"
bootctl install

if [[ -n "$LUKS_PASSPHRASE" ]]; then
  log "Enrolling TPM2 key for LUKS"
  umask 077
  luks_tmp_key="$(mktemp /tmp/luks-key.XXXXXX)"
  printf '%s' "$LUKS_PASSPHRASE" >"$luks_tmp_key"
  systemd-cryptenroll --wipe-slot tpm2 --tpm2-device auto --unlock-key-file="$luks_tmp_key" "$LUKS_PARTITION"
  rm -f "$luks_tmp_key"
fi

ln -sf /dev/null /etc/pacman.d/hooks/90-dracut-install.hook
log "Regenerating initramfs with dracut"
dracut --regenerate-all

ROOT_SOURCE="$(findmnt / -n -o SOURCE)"
ROOT_FSTYPE="$(findmnt / -n -o FSTYPE)"
LVM_VG_NAME="$(lvs --noheadings -o vg_name "$ROOT_SOURCE" | awk '{$1=$1; print $1}')"
LVM_LV_NAME="$(lvs --noheadings -o lv_name "$ROOT_SOURCE" | awk '{$1=$1; print $1}')"
LUKS_UUID="$(blkid -s UUID -o value "$LUKS_PARTITION")"

LVM_ARG="rd.lvm.lv=${LVM_VG_NAME}/${LVM_LV_NAME}"
LUKS_ARG=""
if [[ -n "$LUKS_UUID" ]]; then
  LUKS_ARG="rd.luks.uuid=luks-${LUKS_UUID}"
fi

CMDLINE="${LUKS_ARG} ${LVM_ARG} root=${ROOT_SOURCE} rootfstype=${ROOT_FSTYPE} rootflags=rw,relatime"
mkdir -p /etc/kernel
printf '%s\n' "$CMDLINE" >/etc/kernel/cmdline

log "Generated /etc/kernel/cmdline"
log "$CMDLINE"

log "Enabling NetworkManager"
systemctl enable NetworkManager
