{
  description = "NixOS replacement for the Arch install scripts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix.url = "github:Mic92/sops-nix";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    dotfiles = {
      url = "github:kadencartwright/dotfiles";
      flake = false;
    };

    onedark-wallpapers = {
      url = "github:Narmis-E/onedark-wallpapers";
      flake = false;
    };

    tm = {
      url = "github:kadencartwright/tm";
      flake = false;
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      disko,
      home-manager,
      sops-nix,
      ...
    }:
    {
      nixosConfigurations.laptop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs;
        };

        modules = [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          sops-nix.nixosModules.sops

          ./hosts/laptop/default.nix
          ./hosts/laptop/disko.nix
          ./hosts/laptop/hardware-configuration.nix
        ];
      };
    };
}
