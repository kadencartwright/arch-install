{ lib, pkgs, ... }:
{
  imports = [
    ../../modules/installer-runtime.nix
    ../../modules/storage-disko.nix
    ../../modules/base.nix
    ../../modules/boot.nix
    ../../modules/users.nix
    ../../modules/desktop-hyprland.nix
    ../../modules/dotfiles-bootstrap.nix
  ];

  networking.hostName = lib.mkDefault "arch-host";

  # Enables local vm-test disko formatting without external secret staging.
  install.luksPasswordFile = lib.mkDefault "${pkgs.writeText "vm-test-luks-passphrase" "nixos-vm-test-passphrase"}";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
