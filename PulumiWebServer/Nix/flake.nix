{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops.url = "github:Mic92/sops-nix";
  };

  outputs = {
    self,
    nixpkgs,
    sops,
    home-manager,
  } @ inputs: {
    nixosConfigurations.default = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        (import ./configuration.nix (inputs // {inherit inputs;}))
        sops.nixosModules.sops
      ];
    };
    nix.registry.nixpkgs.flake = nixpkgs;
  };
}
