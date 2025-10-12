{nixpkgs, ...}: let
  lib = nixpkgs.lib;
  # TODO: how can I get this passed in?
  pkgs = nixpkgs.legacyPackages."x86_64-linux";
  userConfig = lib.importJSON ./config.json;
  sshKeys = lib.importJSON ./ssh-keys.json;
in {
  imports = [
    ./sops.nix
    ./apps/apps.nix
    ./radicale/radicale-config.nix
    ./syncthing/syncthing-config.nix
    ./gitea/gitea-config.nix
    ./miniflux/miniflux.nix
    ./userconfig.nix
    ./nginx/nginx.nix
    ./woodpecker/woodpecker.nix
    ./prometheus/prometheus.nix
    ./grafana/grafana.nix
    ./puregym/puregym.nix
    # generated at runtime by nixos-infect and copied here
    ./hardware-configuration.nix
    ./networking.nix
    # ./whisper/whisper.nix
  ];

  services.radicale-config.domain = userConfig.domain;
  services.radicale-config.subdomain = "calendar";
  services.radicale-config.enableGit = true;
  services.userconfig.user = userConfig.remoteUsername;
  services.userconfig.sshKeys = sshKeys;
  services.nginx-config.domain = userConfig.domain;
  services.nginx-config.email = userConfig.acmeEmail;
  services.nginx-config.webrootSubdomain = "www";
  services.nginx-config.staging = true;
  services.gitea-config.subdomain = "gitea";
  services.gitea-config.domain = userConfig.domain;
  services.miniflux-config.subdomain = "rss";
  services.miniflux-config.domain = userConfig.domain;
  services.woodpecker-config.domain = userConfig.domain;
  # A small pun here: we assume that the Gitea/Woodpecker username
  # is the same as the remote username.
  services.woodpecker-config.admin-users = [userConfig.remoteUsername];
  services.grafana-config.domain = userConfig.domain;
  services.prometheus-config.domain-exporter-domains = [userConfig.domain];
  services.puregym-config.domain = userConfig.domain;
  services.puregym-config.subdomain = "puregym";
  services.apps-config.subdomain = "apps";
  services.apps-config.domain = userConfig.domain;
  # services.whisper-config.domain = userConfig.domain;
  # services.whisper-config.subdomain = "whisper";
  services.syncthing-config.subdomain = "syncthing";
  services.syncthing-config.domain = userConfig.domain;

  services.journald.extraConfig = "SystemMaxUse=100M";

  system.stateVersion = "23.05";

  nix = {
    settings = {
      auto-optimise-store = true;
      experimental-features = ["nix-command" "flakes"];
    };
    package = pkgs.nixVersions.latest;
    extraOptions = ''
      experimental-features = ca-derivations flakes
    '';
  };

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;
  networking.hostName = userConfig.name;
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = sshKeys;

  virtualisation.docker = {
    enable = true;
  };

  users.extraGroups.docker.members = [userConfig.remoteUsername];

  security.pam.loginLimits = [
    {
      domain = "*";
      type = "soft";
      item = "nofile";
      value = "8192";
    }
  ];
}
