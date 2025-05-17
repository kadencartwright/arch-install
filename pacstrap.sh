#!/bin/env sh
# #########################
# install dependencies
# #########################
# gum
echo "Running Pacstrap"
pacstrap -K /mnt base linux base-devel linux-firmware lvm2 neovim git \
    networkmanager amd-ucode man-db man-pages  dracut bluez bluez-utils rpcbind go
