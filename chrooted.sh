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
echo -n "$PASSWORD" | passwd --stdin
echo "creating user: 'k'"
USERNAME=k
useradd $USERNAME -m 



su - k -c /root/install-yay.sh 
echo "setting password for user: 'k'"
echo -n "$PASSWORD" | passwd $USERNAME --stdin
usermod -aG wheel $USERNAME
echo '%wheel ALL=(ALL:ALL) ALL' | sudo EDITOR='tee -a' visudo
# set hostname
echo $HOSTNAME > /etc/hostname

echo "Running bootctl install"
bootctl install

echo "Running dracut"
dracut --regenerate-all 

echo "enabling NetworkManager service"
systemctl enable NetworkManager
