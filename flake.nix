{
  description = "Web server flake";
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
        projectFile = "./PulumiWebServer/PulumiWebServer.fsproj";
        testProjectFile = "./PulumiWebServer.Test/PulumiWebServer.Test.fsproj";
        pname = "PulumiWebServer";
        dotnet-sdk = pkgs.dotnetCorePackages.sdk_9_0;
        dotnet-runtime = pkgs.dotnetCorePackages.runtime_9_0;
        version = "0.0.1";
        dotnetTool = toolName: toolVersion: sha256:
          pkgs.stdenvNoCC.mkDerivation rec {
            name = toolName;
            version = toolVersion;
            nativeBuildInputs = [pkgs.makeWrapper];
            src = pkgs.fetchNuGet {
              pname = name;
              version = version;
              sha256 = sha256;
              installPhase = ''mkdir -p $out/bin && cp -r tools/*/any/* $out/bin'';
            };
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/lib"
              cp -r ./bin/* "$out/lib"
              makeWrapper "${dotnet-runtime}/bin/dotnet" "$out/bin/${name}" --add-flags "$out/lib/${name}.dll"
              runHook postInstall
            '';
          };
      in {
        packages = let
          deps = builtins.fromJSON (builtins.readFile ./nix/deps.json);
        in {
          fantomas = dotnetTool "fantomas" (builtins.fromJSON (builtins.readFile ./.config/dotnet-tools.json)).tools.fantomas.version (builtins.head (builtins.filter (elem: elem.pname == "fantomas") deps)).hash;
          default = pkgs.buildDotnetModule {
            inherit pname version projectFile testProjectFile dotnet-sdk dotnet-runtime;
            src = ./.;
            nugetDeps = ./nix/deps.json; # `nix build .#default.fetch-deps && ./result nix/deps.json`
            doCheck = true;
          };
        };
        devShells = let
          requirements = [dotnet-sdk pkgs.git pkgs.alejandra pkgs.nodePackages.markdown-link-check pkgs.jq];
        in {
          default = pkgs.mkShell {
            buildInputs =
              [
                pkgs.pulumi-bin
                pkgs.apacheHttpd
                pkgs.sops
                pkgs.age
                pkgs.ssh-to-age
                pkgs.nixos-rebuild
                pkgs.gnused
                pkgs.python3
              ]
              ++ requirements;
            shellHook = ''
              export PULUMI_SKIP_UPDATE_CHECK=1
            '';
          };
          ci = pkgs.mkShell {
            buildInputs = requirements;
          };
        };
      }
    );
}
