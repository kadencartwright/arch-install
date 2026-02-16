{ config, pkgs, ... }:
let
  username = config.install.username;
in
{
  users.mutableUsers = false;

  users.users.${username} = {
    isNormalUser = true;
    createHome = true;
    description = username;
    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
      "video"
      "input"
    ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;

  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
  };
}
