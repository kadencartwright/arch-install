#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

echo "Running pacstrap"
pacstrap -K /mnt \
  base linux base-devel linux-firmware lvm2 neovim git \
  networkmanager amd-ucode intel-ucode man-db man-pages dracut \
  bluez bluez-utils rpcbind go zsh
