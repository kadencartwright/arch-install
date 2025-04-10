#!/bin/env sh
# pacman hook to update systemd boot
mkdir -p /etc/pacman.d/hooks
cp /root/cfgs/95-systemd-boot.hook /etc/pacman.d/hooks/95-systemd-boot.hook

cp /root/cfgs/dracut-install.sh /usr/local/bin/dracut-install.sh

cp /root/cfgs/dracut-remove.sh /usr/local/bin/dracut-remove.sh

cp /root/cfgs/90-dracut-install.hook /etc/pacman.d/hooks/90-dracut-install.hook

cp /root/cfgs/60-dracut-remove.hook /etc/pacman.d/hooks/60-dracut-remove.hook

cp /root/cfgs/hostonly.conf /etc/dracut.conf.d/hostonly.conf
cp /root/cfgs/uefi.conf /etc/dracut.conf.d/uefi.conf

grep "^Color" /etc/pacman.conf >/dev/null || sed -i "s/^#Color/Color/" /etc/pacman.conf
grep "ILoveCandy" /etc/pacman.conf >/dev/null || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
grep "^ParallelDownloads" /etc/pacman.conf >/dev/null || sed -i "s/^#ParallelDownloads/ParallelDownloads/" /etc/pacman.conf
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

chmod +x /usr/local/bin/dracut-install.sh
chmod +x /usr/local/bin/dracut-remove.sh
