# NixOS Package Mapping

This maps the current Arch package lists to the first NixOS config. Package names should be validated with `nix search` before the real hardware install.

## `packages/wm.txt`

| Arch package | NixOS destination | Nixpkgs/module candidate | Status |
| --- | --- | --- | --- |
| `alacritty` | Home Manager + system package | `programs.alacritty`, `pkgs.alacritty` | Added |
| `bitwarden` | User app | `pkgs.bitwarden-desktop` | Later |
| `brightnessctl` | System package | `pkgs.brightnessctl` | Added |
| `btop` | Home Manager/system package | `pkgs.btop` | Added |
| `chromium` | User app | `pkgs.chromium` | Later |
| `vivaldi` | User app, unfree | `pkgs.vivaldi` | Later |
| `fprintd` | Service | `services.fprintd.enable` | Added |
| `fuzzel` | System/Home Manager package | `pkgs.fuzzel` | Added |
| `gnome-keyring` | Service/package | `services.gnome.gnome-keyring.enable` | Added |
| `hypridle` | System package | `pkgs.hypridle` | Added |
| `hyprland` | Program module | `programs.hyprland.enable` | Added |
| `hyprlock` | System package | `pkgs.hyprlock` | Added |
| `hyprpaper` | System package | `pkgs.hyprpaper` | Added |
| `hyprpolkitagent` | Session package | `pkgs.hyprpolkitagent` | Later |
| `hyprpicker` | System package | `pkgs.hyprpicker` | Added |
| `hyprshot` | Screenshot tooling | `grim`, `slurp`, custom wrapper if needed | Partial |
| `libfprint` | Service dependency | via `services.fprintd` | Added |
| `luarocks` | Dev/editor package | `pkgs.luarocks` | Later |
| `network-manager-applet` | System package | `pkgs.networkmanagerapplet` | Added |
| `nwg-displays` | System package | `pkgs.nwg-displays` | Added |
| `nwg-look` | System package | `pkgs.nwg-look` | Added |
| `pavucontrol` | System package | `pkgs.pavucontrol` | Added |
| `pipewire` | Service | `services.pipewire.enable` | Added |
| `pipewire-alsa` | Service | `services.pipewire.alsa.enable` | Added |
| `pipewire-audio` | Service | `services.pipewire` | Added |
| `pipewire-jack` | Service | `services.pipewire.jack.enable` | Added |
| `pipewire-pulse` | Service | `services.pipewire.pulse.enable` | Added |
| `power-profiles-daemon` | Service | `services.power-profiles-daemon.enable` | Added |
| `qpwgraph` | System package | `pkgs.qpwgraph` | Added |
| `rustup` | Dev tool | `pkgs.rustup` or dev shells | Later |
| `swaync` | System package | `pkgs.swaynotificationcenter` | Added |
| `thunar` | System package/service integration | `pkgs.thunar`, `services.gvfs`, `services.tumbler` | Added |
| `thunar-archive-plugin` | Desktop package | `pkgs.xfce.thunar-archive-plugin` | Later |
| `thunar-volman` | Desktop package | `pkgs.xfce.thunar-volman` | Later |
| `tpm2-tools` | Hardware package | `pkgs.tpm2-tools` | Added |
| `tpm2-tss` | Hardware package | `pkgs.tpm2-tss` | Added |
| `ttf-dejavu-nerd` | Font | `pkgs.dejavu_fonts`, Nerd Font variant if needed | Partial |
| `ttf-font-awesome` | Font | `pkgs.font-awesome` | Added |
| `ttf-meslo-nerd` | Font | `pkgs.nerd-fonts.meslo-lg` | Added |
| `tumbler` | Service | `services.tumbler.enable` | Added |
| `waybar` | System/Home Manager package | `pkgs.waybar` | Added |
| `xdg-desktop-portal-hyprland` | Program module | via `programs.hyprland` | Added |
| `zsh` | Program/user shell | `programs.zsh.enable`, `users.users.k.shell` | Added |
| `zsh-autosuggestions` | Home Manager | `programs.zsh.autosuggestion.enable` | Added |
| `zsh-completions` | Home Manager | `programs.zsh.enableCompletion` | Added |
| `ripgrep` | Home Manager/system package | `pkgs.ripgrep` | Added |
| `systemd-ukify` | Boot hardening | NixOS UKI/systemd tooling | Later |
| `otf-font-awesome` | Font | `pkgs.font-awesome` | Added |
| `profile-sync-daemon` | User service | package/module if still wanted | Later |
| `thunderbird` | User app | `pkgs.thunderbird` | Later |
| `lazygit` | Home Manager package | `pkgs.lazygit` | Added |

## `packages/aur.txt`

| AUR package | NixOS destination | Nixpkgs/module candidate | Status |
| --- | --- | --- | --- |
| `dracut-ukify` | Boot hardening | NixOS UKI/initrd options | Later |
| `bemoji` | User package | `pkgs.bemoji` if available, otherwise custom package | Later |
| `bluetuith-bin` | User package | `pkgs.bluetuith` if available | Later |
| `reflector-simple` | Removed | NixOS uses pinned flake inputs, not mirror ranking for system config | Excluded |
| `tmux-sessionizer-bin` | User script/package | custom Home Manager script | Later |
| `ttf-apple-emoji` | Font | possible unfree/custom font package | Later |
| `ttf-segoe-ui-variable` | Font | possible unfree/custom font package | Later |
| `spotify` | User app, unfree | `pkgs.spotify` | Later |
