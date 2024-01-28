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
        projectFile = "./PulumiWebServer/PulumiWebServer.fsproj";
        testProjectFile = "./PulumiWebServer.Test/PulumiWebServer.Test.fsproj";
        pname = "PulumiWebServer";
        dotnet-sdk = pkgs.dotnet-sdk_8;
        dotnet-runtime = pkgs.dotnetCorePackages.runtime_8_0;
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
              installPhase = ''mkdir -p $out/bin && cp -r tools/net6.0/any/* $out/bin'';
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
        packages = {
          fantomas = dotnetTool "fantomas" (builtins.fromJSON (builtins.readFile ./.config/dotnet-tools.json)).tools.fantomas.version "sha256-Jmo7s8JMdQ8SxvNvPnryfE7n24mIgKi5cbgNwcQw3yU=";
          fetchDeps = let
            flags = [];
            runtimeIds = map (system: pkgs.dotnetCorePackages.systemToDotnetRid system) dotnet-sdk.meta.platforms;
          in
            pkgs.writeShellScriptBin "fetch-${pname}-deps" (builtins.readFile (pkgs.substituteAll {
              src = ./nix/fetchDeps.sh;
              pname = pname;
              binPath = pkgs.lib.makeBinPath [pkgs.coreutils dotnet-sdk (pkgs.nuget-to-nix.override {inherit dotnet-sdk;})];
              projectFiles = toString (pkgs.lib.toList projectFile);
              testProjectFiles = toString (pkgs.lib.toList testProjectFile);
              rids = pkgs.lib.concatStringsSep "\" \"" runtimeIds;
              packages = dotnet-sdk.packages;
              storeSrc = pkgs.srcOnly {
                src = ./.;
                pname = pname;
                version = version;
              };
            }));
          default = pkgs.buildDotnetModule {
            pname = pname;
            version = version;
            src = ./.;
            projectFile = projectFile;
            nugetDeps = ./nix/deps.nix;
            doCheck = true;
            dotnet-sdk = dotnet-sdk;
            dotnet-runtime = dotnet-runtime;
          };
        };
        devShells = let
          requirements = [pkgs.dotnet-sdk_8 pkgs.git pkgs.alejandra pkgs.nodePackages.markdown-link-check pkgs.jq];
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
