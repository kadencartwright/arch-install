#!/bin/env sh
echo "Setting Timezone"
ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime

hwclock --systohc
sed -i -e 's|#en_US.UTF-8 UTF-8|en_US.UTF-8 UTF-8|' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >/etc/locale.conf

echo -n "$PASSWORD" | passwd --stdin
USERNAME=k
useradd $USERNAME -m 
echo -n "$PASSWORD" | passwd $USERNAME --stdin
usermod -aG wheel $USERNAME
echo '%wheel ALL=(ALL:ALL) ALL' | sudo EDITOR='tee -a' visudo
# set hostname
echo $HOSTNAME > /etc/hostname

bootctl install

dracut --regenerate-all 

