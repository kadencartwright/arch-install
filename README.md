# Arch Install Scripts

This repository contains helper scripts to configure new arch linux machines

It uses 
- LUKS on lvm
- systemd-boot
- dracut
## TODO:
set up tpm auto unlocking
    - use systemd-cryptenroll
        - sudo systemd-cryptenroll --wipe-slot tpm2 --tpm2-device auto $LUKS_PARTITION
    - install tpm2 and tpm tools packages
        sudo pacman -S tpm2-tss tpm2-tools
    - set dracut to use the following options
            add_dracutmodules+=" tpm2-tss crypt "
            add_modules+=" tpm2-tss crypt "
