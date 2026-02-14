{ config, lib, pkgs, ... }:
let
  cfg = config.install;
  username = cfg.username;
  homeDir = "/home/${username}";
  markerFile = "${homeDir}/.local/state/dotfiles_bootstrapped";
in
{
  systemd.services.dotfiles-bootstrap = lib.mkIf cfg.dotfiles.enable {
    description = "One-time dotfiles bootstrap";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "home.mount" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [ git gnumake bash coreutils ];
    serviceConfig = {
      Type = "oneshot";
      User = username;
      Group = username;
      WorkingDirectory = homeDir;
    };
    script = ''
      set -euo pipefail

      if [ -f "${markerFile}" ]; then
        exit 0
      fi

      mkdir -p "${homeDir}/code" "${homeDir}/.local/state"

      if [ ! -d "${homeDir}/code/dotfiles/.git" ]; then
        git clone "${cfg.dotfiles.repoUrl}" "${homeDir}/code/dotfiles"
      fi

      if [ ! -d "${homeDir}/code/dotman/.git" ]; then
        git clone "${cfg.dotfiles.dotmanRepoUrl}" "${homeDir}/code/dotman"
      fi

      cd "${homeDir}/code/dotman"
      make

      cd "${homeDir}/code/dotfiles"
      "${homeDir}/code/dotman/bin/dotman" link -f "${cfg.dotfiles.manifestPath}"

      touch "${markerFile}"
    '';
  };
}
