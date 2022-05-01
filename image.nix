{pkgs ? import <nixpkgs> {system = "x86_64-linux";}}: let
  config = {
    imports = [<nixpkgs/nixos/modules/virtualisation/digital-ocean-image.nix>];
  };
in
  (pkgs.pkgsCross.aarch64-multiplatform-musl.nixos config).digitalOceanImage
