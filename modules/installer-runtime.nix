{ lib, ... }:
let
  types = lib.types;
in
{
  options.install = {
    username = lib.mkOption {
      type = types.str;
      default = "k";
      description = "Primary interactive user account.";
    };

    timezone = lib.mkOption {
      type = types.str;
      default = "America/Chicago";
      description = "System timezone.";
    };

    enableTpmEnroll = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Enable one-time TPM2 enrollment for the LUKS device.";
    };

    diskDevice = lib.mkOption {
      type = types.str;
      default = "/dev/vda";
      description = "Install target disk used by disko.";
    };

    luksPasswordFile = lib.mkOption {
      type = types.str;
      default = "/var/lib/install/luks-passphrase";
      description = "Path to one-time LUKS passphrase file used during installation.";
    };

    dotfiles = {
      enable = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Enable one-time dotfiles bootstrap service.";
      };

      repoUrl = lib.mkOption {
        type = types.str;
        default = "https://github.com/kadencartwright/dotfiles";
        description = "Dotfiles repository URL.";
      };

      dotmanRepoUrl = lib.mkOption {
        type = types.str;
        default = "https://github.com/kadencartwright/dotman";
        description = "Dotman repository URL.";
      };

      manifestPath = lib.mkOption {
        type = types.str;
        default = "./dotman.toml";
        description = "Dotman manifest path relative to the dotfiles checkout.";
      };
    };
  };
}
