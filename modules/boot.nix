{ config, lib, pkgs, ... }:
let
  cfg = config.install;
in
{
  boot = {
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };

    initrd = {
      systemd.enable = true;
      availableKernelModules = [
        "nvme"
        "ahci"
        "xhci_pci"
        "usbhid"
        "virtio_pci"
        "virtio_blk"
        "dm_crypt"
        "dm_mod"
      ];
      luks.devices.cryptlvm = lib.mkIf cfg.vmTestAutoUnlock {
        keyFile = "/crypto_keyfile.bin";
      };
      secrets = lib.mkIf cfg.vmTestAutoUnlock {
        "/crypto_keyfile.bin" = pkgs.writeText "vm-test-luks-key" "nixos-vm-test-passphrase";
      };
    };
  };

  systemd.services.tpm2-luks-enroll = lib.mkIf cfg.enableTpmEnroll {
    description = "One-time TPM2 enrollment for root LUKS volume";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    path = [ pkgs.systemd pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      ExecStart = pkgs.writeShellScript "tpm2-luks-enroll" ''
        set -euo pipefail

        part_file="/var/lib/install/luks-partition"
        pass_file="/var/lib/install/luks-passphrase"

        if [ ! -r "$part_file" ] || [ ! -r "$pass_file" ]; then
          echo "tpm2-luks-enroll: missing $part_file or $pass_file, skipping enrollment" >&2
          exit 0
        fi

        luks_partition="$(tr -d '\n' < "$part_file")"
        tmp_key="$(mktemp /tmp/luks-key.XXXXXX)"
        trap 'rm -f "$tmp_key" "$part_file" "$pass_file"' EXIT

        cp "$pass_file" "$tmp_key"
        chmod 600 "$tmp_key"

        systemd-cryptenroll \
          --wipe-slot=tpm2 \
          --tpm2-device=auto \
          --unlock-key-file="$tmp_key" \
          "$luks_partition"
      '';
    };
  };
}
