#!/bin/env sh
printenv
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

# set hostname
echo $HOSTNAME > /etc/hostname

bootctl install

dracut --regenerate-all 

