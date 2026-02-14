{ config, ... }:
let
  cfg = config.install;
in
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = cfg.diskDevice;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "fmask=0137" "dmask=0027" ];
            };
          };

          cryptlvm = {
            size = "100%";
            label = "cryptlvm";
            content = {
              type = "luks";
              name = "cryptlvm";
              passwordFile = cfg.luksPasswordFile;
              settings = {
                allowDiscards = true;
              };
              content = {
                type = "lvm_pv";
                vg = "vg1";
              };
            };
          };
        };
      };
    };

    lvm_vg.vg1 = {
      type = "lvm_vg";
      lvs = {
        root = {
          size = "80G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };

        home = {
          size = "100%FREE";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/home";
          };
        };
      };
    };
  };
}
