{
  description = "Web server flake";
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    alejandra.url = "github:kamadorueda/alejandra/1.2.0";
    alejandra.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
    alejandra,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
      in {
        inherit nixpkgs;
        defaultPackage = pkgs.hello;
        devShell = pkgs.mkShell {
          buildInputs = [
            pkgs.pulumi-bin
            pkgs.dotnet-sdk_6
            pkgs.python
            pkgs.git
            alejandra.defaultPackage.${system}
          ];
          shellHook = ''
            export PULUMI_SKIP_UPDATE_CHECK=1
          '';
        };
      }
    );
}
