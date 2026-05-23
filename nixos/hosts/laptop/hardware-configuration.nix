{ lib, ... }:

{
  # Replace this file with the output of nixos-generate-config on the target
  # machine, or let nixos-anywhere generate it during installation.
  boot.initrd.availableKernelModules = lib.mkDefault [ ];
  boot.initrd.kernelModules = lib.mkDefault [ ];
  boot.kernelModules = lib.mkDefault [ ];
  boot.extraModulePackages = lib.mkDefault [ ];
}
