#!/bin/env sh
# #########################
# install dependencies
# #########################
# gum
pacman -Sy --noconfirm gum

PASSPHRASE_UNSET=1
while [[ $PASSPHRASE_UNSET -eq 1 ]]; do
    LUKS_PASSPHRASE=$(gum input --password --placeholder "Enter a LUKS Passphrase: ") 
    LUKS_PASSPHRASE_CONFIRM=$(gum input --password --placeholder "Confirm your LUKS Passphrase: ")
    if [[ "$LUKS_PASSPHRASE" == "$LUKS_PASSPHRASE_CONFIRM" ]]; then
        PASSPHRASE_UNSET=0
    else
        echo "Passphrases are not equal"
    fi
done

PASSWORD_UNSET=1
while [[ $PASSWORD_UNSET -eq 1 ]]; do
    PASSWORD=$(gum input --password --placeholder "Enter a root Password: ") 
    PASSWORD_CONFIRM=$(gum input --password --placeholder "Confirm your root Password: ")
    if [[ "$PASSWORD" == "$PASSWORD_CONFIRM" ]]; then
        PASSWORD_UNSET=0
    else
        echo "Passwords are not equal"
    fi
done
HOSTNAME=$(gum input --placeholder "Enter a hostname") 

# sync system time
timedatectl set-ntp true
#select disk to use

disks=$(fdisk -l 2>/dev/null | awk '/^Disk \//{print substr($2,0,length($2)-1)}' )
selected=$(echo $disks | xargs gum choose --header="Select a disk to use for Arch Linux:")
if [[ -z "$selected" ]]; then
  echo "Error: no disk selected"
  exit 1
fi
# create 2 partitions
# one EFI partition - 1gb
# lvm partition for the rest of the drive
echo "Partitioning disk"
sgdisk --clear -n 1:0:+1G -t 1:ef00 -n 2:0:+0 -t 2:8e00 "${selected}"
string=$(echo $selected*)

partitions=($string)
BOOT_PARTITION="$(echo ${partitions[1]})"
echo "using $BOOT_PARTITION as boot partition"
LUKS_PARTITION="$(echo ${partitions[2]})"
echo "using $LUKS_PARTITION as LUKS partition"

echo "Formatting Boot partition as FAT32"
# format EFI partition
mkfs.fat -F 32 $BOOT_PARTITION 



echo "formatting LUKS Partition"
# create a LUKS partition
echo -n $LUKS_PASSPHRASE | cryptsetup luksFormat $LUKS_PARTITION -

# open the LUKS partition
echo -n $LUKS_PASSPHRASE | cryptsetup open $LUKS_PARTITION cryptlvm --key-file -

echo "Creating Physical Volume on LUKS Partition"
# create physical volume on the LUKS partition
pvcreate /dev/mapper/cryptlvm
# create logical volume group on the physical volume
echo "Creating Volume Group on PV"
VG_NAME="vg1"
vgcreate $VG_NAME /dev/mapper/cryptlvm

echo "Creating root volume"
# create logical volume named root on the volume group with 80 GB of space
VG_ROOT_NAME="root"
lvcreate -L 80G vg1 -n $VG_ROOT_NAME 

echo "Creating home volume"
# create logical volume named home on the volume group with the rest of the space
VG_HOME_NAME="home"
lvcreate -l 100%FREE vg1 -n $VG_HOME_NAME 

echo "formatting Root Volume"
# format root lv partition with ext4 filesystem
VG_ROOT_PATH="/dev/$VG_NAME/$VG_ROOT_NAME"
mkfs.ext4 -m 1 /dev/vg1/root

echo "formatting Home Volume"
# format home lv partition with ext4 filesystem
VG_HOME_PATH="/dev/$VG_NAME/$VG_HOME_NAME"
mkfs.ext4 -m 1 /dev/vg1/home

echo "mounting root volume to /mnt"
# mount the root partition
mount --mkdir /dev/vg1/root /mnt

echo "mounting home volume to /mnt/home"
# mount the home partition
mount --mkdir /dev/vg1/home /mnt/home

echo "mounting boot partition to /mnt/boot"
# mount the EFI partition
mount --mkdir "${BOOT_PARTITION}" /mnt/boot

./pacstrap.sh 

genfstab -U /mnt >> /mnt/etc/fstab
#edit fstab
sed -i 's/fmask=0022/fmask=0137/' /mnt/etc/fstab
sed -i 's/dmask=0022/dmask=0027/' /mnt/etc/fstab
# pacman hook to update systemd boot
#cat <<EOF >/etc/pacman.d/hooks/95-systemd-boot.hook
mkdir -p ./cfgs
cat <<EOF >./cfgs/95-systemd-boot.hook
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Gracefully upgrading systemd-boot...
When = PostTransaction
Exec = /usr/bin/systemctl restart systemd-boot-update.service
EOF
LUKS_UUID=$(blkid -s UUID -o value "${LUKS_PARTITION}")
OPTIONS="nowatchdog rd.luks.uuid=$LUKS_UUID root=$VG_ROOT_PATH"

cat <<'EOF' >./cfgs/dracut-install.sh
#!/bin/bash -e

all=0
lines=()

while read -r line; do
	if [[ "${line}" != */vmlinuz ]]; then
		# triggers when it's a change to dracut files
		all=1
		continue
	fi

	lines+=("/${line%/vmlinuz}")

	pkgbase="$(<"${lines[-1]}/pkgbase")"
	install -Dm644 "/${line}" "/boot/vmlinuz-${pkgbase}"
done

if (( all )); then
	lines=(/usr/lib/modules/*)
fi

for line in "${lines[@]}"; do
	if ! pacman -Qqo "${line}/pkgbase" &> /dev/null; then
		# if pkgbase does not belong to any package then skip this kernel
		continue
	fi

	pkgbase="$(<"${line}/pkgbase")"
	kver="${line##*/}"
	dracut_restore_img="/usr/lib/modules/${kver}/initrd"

	echo ":: Building initramfs for ${pkgbase} (${kver})"
	dracut --force --hostonly --no-hostonly-cmdline ${dracut_restore_img} "${kver}"
	install -Dm644 ${dracut_restore_img} "/boot/initramfs-${pkgbase}.img"

	echo ":: Building fallback initramfs for ${pkgbase} (${kver})"
	dracut --force --no-hostonly "/boot/initramfs-${pkgbase}-fallback.img" "${kver}"
done
EOF
cat <<'EOF' >./cfgs/dracut-remove.sh
#!/usr/bin/env bash

while read -r line; do
    if [[ "$line" == 'usr/lib/modules/'+([^/])'/pkgbase' ]]; then
        read -r pkgbase < "/${line}"
        rm -f "/boot/vmlinuz-${pkgbase}" "/boot/initramfs-${pkgbase}.img" "/boot/initramfs-${pkgbase}-fallback.img"
    fi
done
EOF

cat <<'EOF' >./cfgs/90-dracut-install.hook
[Trigger]
Type = Path
Operation = Install
Operation = Upgrade
Target = usr/lib/modules/*/pkgbase

[Action]
Description = Updating linux initcpios (with dracut!)...
When = PostTransaction
Exec = /usr/local/bin/dracut-install.sh
Depends = dracut
NeedsTargets
EOF

cat <<'EOF' >./cfgs/60-dracut-remove.hook
[Trigger]
Type = Path
Operation = Remove
Target = usr/lib/modules/*/pkgbase

[Action]
Description = Removing linux initcpios...
When = PreTransaction
Exec = /usr/local/bin/dracut-remove.sh
NeedsTargets
EOF

cat <<EOF >./cfgs/hostonly.conf
hostonly="yes"
EOF
cat <<EOF >./cfgs/uefi.conf
uefi="yes"
EOF

cp -r ./cfgs/ /mnt/root/cfgs
cp -r ./packages /mnt/root/packages
cp ./install-hooks.sh /mnt/root/install-hooks.sh
cp ./chrooted.sh /mnt/root/chrooted.sh
cp ./install-yay.sh /mnt/root/install-yay.sh
cp ./install-dotfiles.sh /mnt/root/install-dotfiles.sh
cp ./install-aur-packages.sh /mnt/root/install-aur-packages.sh

( arch-chroot /mnt /root/install-hooks.sh )|& tee install-hooks.log
( PASSWORD=$PASSWORD HOSTNAME=$HOSTNAME arch-chroot /mnt /root/chrooted.sh )|& tee chrooted.log
