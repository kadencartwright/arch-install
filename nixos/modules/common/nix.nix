{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nix.settings.auto-optimise-store = true;

  nixpkgs.config.allowUnfree = true;
}
