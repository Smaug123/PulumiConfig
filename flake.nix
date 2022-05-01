{
  description = "Web server flake";
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
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
            pkgs.nixops
            pkgs.dotnet-sdk_6
          ];
          shellHook = ''
            export PULUMI_SKIP_UPDATE_CHECK=1
          '';
        };
      }
    );
}
