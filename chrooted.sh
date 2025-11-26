#!/bin/env sh
echo "Setting Timezone"
ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime
echo "installing packages for graphical environment"
pacman -S --noconfirm - < /root/packages/wm.txt

hwclock --systohc
sed -i -e 's|#en_US.UTF-8 UTF-8|en_US.UTF-8 UTF-8|' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >/etc/locale.conf

echo "setting password for root user"
echo "root:$PASSWORD" | chpasswd
USERNAME=k
echo "creating user: $USERNAME"
useradd $USERNAME -m 

echo "setting password for user: $USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
usermod -aG wheel $USERNAME
echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

# set default shell
chsh -s $(which zsh) $USERNAME
# copy post install scripts
cp /root/install-yay.sh /home/$USERNAME/
cp /root/install-dotfiles.sh /home/$USERNAME/
cp /root/install-aur-packages.sh /home/$USERNAME/
cp /root/packages/aur.txt /home/$USERNAME/

chown $USERNAME /home/$USERNAME/install-yay.sh
chown $USERNAME /home/$USERNAME/install-aur-packages.sh
chown $USERNAME /home/$USERNAME/aur.txt
chown $USERNAME /home/$USERNAME/install-dotfiles.sh

su - $USERNAME -c /home/$USERNAME/install-yay.sh 
su - $USERNAME -c /home/$USERNAME/install-aur-packages.sh 
su - $USERNAME -c /home/$USERNAME/install-dotfiles.sh

# Revert sudoers to require password
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
# set hostname
echo $HOSTNAME > /etc/hostname


echo "Running bootctl install"
bootctl install

echo "Enrolling TPM2"
echo -n "$LUKS_PASSPHRASE" > /tmp/luks-key
systemd-cryptenroll --wipe-slot tpm2 --tpm2-device auto --unlock-key-file=/tmp/luks-key $LUKS_PARTITION
rm /tmp/luks-key

ln -s /dev/null /etc/pacman.d/hooks/90-dracut-install.hook
echo "Running dracut"
dracut --regenerate-all 

# 1. Identify the root device currently mounted
ROOT_SOURCE=$(findmnt / -n -o SOURCE)
ROOT_FSTYPE=$(findmnt / -n -o FSTYPE)

# 2. Get LVM details
eval $(lvs --noheadings --nameprefixes -o vg_name,lv_name "$ROOT_SOURCE")
LVM_ARG="rd.lvm.lv=${LVM2_VG_NAME}/${LVM2_LV_NAME}"

# 3. Get LUKS details 
LUKS_UUID=$(lsblk -s -p -n -o UUID,FSTYPE "$ROOT_SOURCE" | grep crypto_LUKS | awk '{print $1}')

if [ -n "$LUKS_UUID" ]; then
    LUKS_ARG="rd.luks.uuid=luks-${LUKS_UUID}"
fi

CMDLINE="${LUKS_ARG} ${LVM_ARG} root=/dev/mapper/${LVM2_VG_NAME}-${LVM2_LV_NAME} rootfstype=${ROOT_FSTYPE} rootflags=rw,relatime"

# 5. Write to file
mkdir -p /etc/kernel
echo "$CMDLINE" > /etc/kernel/cmdline

echo "Generated Configuration:"
echo "$CMDLINE"

echo "enabling NetworkManager service"
systemctl enable NetworkManager
