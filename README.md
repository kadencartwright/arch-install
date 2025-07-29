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
    - set dracut to use the following options
            add_dracutmodules+=" tpm2-tss crypt "
            add_modules+=" tpm2-tss crypt "
set up uki gen
    - yay -S dracut-ukify 
Set up lid switch suspend config
- /etc/systemd/logind.conf
        HandleLidSwitch=suspend
        HandleLidSwitchExternalPower=ignore
        HandleLidSwitchDocked=ignore

