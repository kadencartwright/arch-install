#!/bin/env sh
# #########################
# install dependencies
# #########################
# gum
echo "Running Pacstrap"
pacstrap -K /mnt base linux base-devel linux-firmware lvm2 neovim git \
    networkmanager amd-ucode man-db man-pages pipewire pipewire-jack \
    pipewire-audio pipewire-alsa hyprland xdg-desktop-portal-hyprland \
    zsh zsh-autosuggestions zsh-completions hyprpolkitagent power-profiles-daemon \
    ttf-meslo-nerd ttf-dejavu-nerd pipewire-pulse network-manager-applet dracut \
    bluez bluez-utils rpcbind
