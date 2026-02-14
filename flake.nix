{
  description = "NixOS configuration and installer flow for arch-install migration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
    nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
      nixos-anywhere,
      ...
    }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
      pkgs = import nixpkgs { inherit system; };
    in
    {
      nixosConfigurations.arch-host = lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          ./hosts/arch-host/default.nix
        ];
      };

      packages.${system}.run-nixos-anywhere = pkgs.writeShellApplication {
        name = "run-nixos-anywhere";
        runtimeInputs = [ pkgs.bash ];
        text = ''
          exec "${self}/scripts/run-nixos-anywhere.sh" "$@"
        '';
      };

      checks.${system}.arch-host-eval = self.nixosConfigurations.arch-host.config.system.build.toplevel;
      checks.${system}.nixos-anywhere-package = nixos-anywhere.packages.${system}.default;
    };
}
