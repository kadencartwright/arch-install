#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

mkdir -p /etc/pacman.d/hooks /etc/dracut.conf.d
cp /root/cfgs/95-systemd-boot.hook /etc/pacman.d/hooks/95-systemd-boot.hook
cp /root/cfgs/hostonly.conf /etc/dracut.conf.d/hostonly.conf
cp /root/cfgs/uefi.conf /etc/dracut.conf.d/uefi.conf

grep -q '^Color' /etc/pacman.conf || sed -i 's/^#Color/Color/' /etc/pacman.conf
grep -q 'ILoveCandy' /etc/pacman.conf || sed -i '/#VerbosePkgLists/a ILoveCandy' /etc/pacman.conf
grep -q '^ParallelDownloads' /etc/pacman.conf || sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf
