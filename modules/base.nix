{ config, pkgs, ... }:
let
  cfg = config.install;
in
{
  nixpkgs.config.allowUnfree = true;

  hardware.enableRedistributableFirmware = true;

  time.timeZone = cfg.timezone;

  i18n.defaultLocale = "en_US.UTF-8";

  console = {
    keyMap = "us";
  };

  networking.networkmanager = {
    enable = true;
    wifi.backend = "iwd";
  };

  networking.wireless.iwd.enable = true;

  services = {
    openssh.enable = true;
    fstrim.enable = true;
  };

  environment.systemPackages = with pkgs; [
    git
    neovim
    go
    gnumake
    python3
    ripgrep
  ];

  system.stateVersion = "25.05";
}
