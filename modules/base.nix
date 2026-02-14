{ config, pkgs, ... }:
let
  cfg = config.install;
in
{
  time.timeZone = cfg.timezone;

  i18n.defaultLocale = "en_US.UTF-8";

  console = {
    keyMap = "us";
  };

  networking.networkmanager.enable = true;

  services = {
    openssh.enable = true;
    fstrim.enable = true;
  };

  environment.systemPackages = with pkgs; [
    git
    neovim
    go
    python3
    ripgrep
  ];

  system.stateVersion = "25.05";
}
