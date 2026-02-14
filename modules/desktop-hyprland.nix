{ lib, pkgs, ... }:
let
  optionalPackage = name:
    lib.optional (builtins.hasAttr name pkgs) (builtins.getAttr name pkgs);

  optionalAttrPath = path:
    let
      pkg = lib.attrByPath path null pkgs;
    in
    lib.optional (pkg != null) pkg;
in
{
  programs.hyprland.enable = true;

  services = {
    displayManager.gdm.enable = false;
    greetd = {
      enable = true;
      settings = {
        default_session = {
          user = "greeter";
          command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd Hyprland";
        };
      };
    };

    xserver.enable = true;
    libinput.enable = true;
    fprintd.enable = true;
    gnome.gnome-keyring.enable = true;
    tumbler.enable = true;
    upower.enable = true;
    power-profiles-daemon.enable = true;
    blueman.enable = true;
  };

  hardware = {
    bluetooth.enable = true;
    pulseaudio.enable = false;
  };

  security.polkit.enable = true;

  xdg.portal = {
    enable = true;
    xdgOpenUsePortal = true;
    extraPortals =
      [ pkgs.xdg-desktop-portal-gtk ]
      ++ optionalPackage "xdg-desktop-portal-hyprland";
  };

  programs.thunar.enable = true;

  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    jack.enable = true;
  };

  fonts.packages =
    (optionalPackage "font-awesome")
    ++ (optionalAttrPath [ "nerd-fonts" "dejavu-sans-mono" ])
    ++ (optionalAttrPath [ "nerd-fonts" "meslo-lg" ]);

  environment.systemPackages = with pkgs; [
    alacritty
    btop
    brightnessctl
    chromium
    fuzzel
    hypridle
    hyprlock
    hyprpaper
    hyprshot
    lazygit
    libfprint
    luarocks
    networkmanagerapplet
    nwg-displays
    nwg-look
    pavucontrol
    qpwgraph
    rustup
    swaynotificationcenter
    thunderbird
    waybar
    zsh-autosuggestions
    zsh-completions
    profile-sync-daemon
  ]
  ++ optionalPackage "bitwarden-desktop"
  ++ optionalPackage "hyprpolkitagent"
  ++ optionalPackage "otf-font-awesome"
  ++ optionalPackage "spotify"
  ++ optionalPackage "tpm2-tools"
  ++ optionalPackage "tpm2-tss";
}
