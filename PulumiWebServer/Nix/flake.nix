{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    website = {
      url = "github:Smaug123/static-site-pipeline";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    puregym-client = {
      url = "git+https://gitea.patrickstevens.co.uk/patrick/puregym-unofficial-dotnet";
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
    puregym-client,
  } @ inputs: let
    system = "x86_64-linux";
  in {
    nixosConfigurations.default = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit system;
        website = website.packages.${system}.default;
        puregym-client = puregym-client.packages.${system}.default;
      };
      modules = [
        (import ./configuration.nix (inputs // {inherit inputs;}))
        sops.nixosModules.sops
      ];
    };
    nix.registry.nixpkgs.flake = nixpkgs;
  };
}
