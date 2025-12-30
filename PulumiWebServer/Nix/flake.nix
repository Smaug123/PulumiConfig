{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    website = {
      url = "github:Smaug123/static-site-pipeline";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    puregym-client = {
      url = "git+https://gitea.patrickstevens.co.uk/patrick/puregym-unofficial-dotnet";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    whisper-packages = {
      url = "github:Smaug123/whisper.cpp/nix-small";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    robocop = {
      url = "github:Smaug123/robocop";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    robocop-dashboard = {
      url = "github:Smaug123/robocop-dashboard";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    sops,
    home-manager,
    website,
    puregym-client,
    whisper-packages,
    robocop,
    robocop-dashboard,
  } @ inputs: let
    system = "x86_64-linux";
  in {
    nixosConfigurations.default = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit system nixpkgs;
        website = website.packages.${system}.default;
        puregym-client = puregym-client.packages.${system}.default;
        whisper-packages = whisper-packages.packages.${system};
        robocop = robocop.packages.${system}.default;
        robocop-dashboard = robocop-dashboard.packages.${system}.default;
      };
      modules = [
        ./configuration.nix
        sops.nixosModules.sops
      ];
    };
    nix.registry.nixpkgs.flake = nixpkgs;
  };
}
