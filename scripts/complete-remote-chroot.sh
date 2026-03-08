#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

REMOTE_HOST="${1:-root@10.10.26.137}"

ssh "$REMOTE_HOST" 'bash -se' <<'EOF'
set -euo pipefail

install -d -m 700 /mnt/root/.arch-installer-secrets
install -m 600 /root/.arch-installer-config /mnt/root/.arch-installer-config
install -m 600 /root/.arch-installer-secrets/root_password /mnt/root/.arch-installer-secrets/root_password
install -m 600 /root/.arch-installer-secrets/user_password /mnt/root/.arch-installer-secrets/user_password
install -m 600 /root/.arch-installer-secrets/luks_passphrase /mnt/root/.arch-installer-secrets/luks_passphrase

arch-chroot /mnt /bin/bash -se <<'CHROOT'
set -euo pipefail

source /root/.arch-installer-config

chmod 755 /etc
chmod 755 /var/cache/pacman /var/lib/pacman /var/lib/pacman/local
chmod -R a+rX /var/lib/pacman/local

printf '%%wheel ALL=(ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

install -m 0755 /root/install-yay.sh /home/k/install-yay.sh
install -m 0755 /root/install-aur-packages.sh /home/k/install-aur-packages.sh
install -m 0755 /root/install-dotfiles.sh /home/k/install-dotfiles.sh
install -m 0644 /root/packages/aur.txt /home/k/aur.txt
chown k:k /home/k/install-yay.sh /home/k/install-aur-packages.sh /home/k/install-dotfiles.sh /home/k/aur.txt

su - k -c /home/k/install-yay.sh
su - k -c /home/k/install-aur-packages.sh
su - k -c /home/k/install-dotfiles.sh

printf '%%wheel ALL=(ALL:ALL) ALL\n' >/etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

printf '%s\n' "$HOSTNAME" >/etc/hostname

bootctl install
ln -sf /dev/null /etc/pacman.d/hooks/90-dracut-install.hook
dracut --regenerate-all

if [[ -s /root/.arch-installer-secrets/luks_passphrase && -b "$LUKS_PARTITION" ]]; then
    LUKS_KEY_FILE="$(mktemp /tmp/luks-key.XXXXXX)"
    chmod 600 "$LUKS_KEY_FILE"
    cp /root/.arch-installer-secrets/luks_passphrase "$LUKS_KEY_FILE"
    systemd-cryptenroll --wipe-slot tpm2 --tpm2-device auto --unlock-key-file="$LUKS_KEY_FILE" "$LUKS_PARTITION"
    rm -f "$LUKS_KEY_FILE"
fi

systemctl enable NetworkManager

rm -f /root/.arch-installer-config
rm -f /root/.arch-installer-secrets/root_password /root/.arch-installer-secrets/user_password /root/.arch-installer-secrets/luks_passphrase
rmdir /root/.arch-installer-secrets 2>/dev/null || true
CHROOT
EOF
