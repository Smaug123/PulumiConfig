{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/697312fb824243bd7bf82d2a3836a11292614109";
    website = {
      url = "github:Smaug123/static-site-pipeline";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
    website,
  } @ inputs: let
    system = "x86_64-linux";
  in {
    nixosConfigurations.default = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit system;
        website = website.packages.${system}.default;
      };
      modules = [
        (import ./configuration.nix (inputs // {inherit inputs;}))
        sops.nixosModules.sops
      ];
    };
    nix.registry.nixpkgs.flake = nixpkgs;
  };
}
