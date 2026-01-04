{
  nixpkgs,
  config,
  ...
}: let
  lib = nixpkgs.lib;
  # TODO: how can I get this passed in?
  pkgs = nixpkgs.legacyPackages."x86_64-linux";
  userConfig = lib.importJSON ./config.json;
  sshKeys = lib.importJSON ./ssh-keys.json;
  prometheusCfg = config.services.prometheus-container;
in {
  imports =
    [
      ./apps/apps.nix
      ./radicale/radicale-container.nix
      ./syncthing/syncthing-container.nix
      ./gitea/gitea-container.nix
      ./miniflux/miniflux-container.nix
      ./userconfig.nix
      ./nginx/nginx.nix
      ./woodpecker/woodpecker.nix
      ./prometheus/prometheus-container.nix
      ./grafana/grafana-container.nix
      ./puregym/puregym-container.nix
      ./robocop/robocop-container.nix
      ./secrets/secrets.nix
      # ./whisper/whisper.nix
    ]
    ++ (
      if true
      then [
        ./hardware/digitalocean.nix
        ./networking/digitalocean.nix
      ]
      else [
        ./hardware/nixbox.nix
        ./networking/nixbox.nix
      ]
    );

  services.radicale-container.enable = true;
  services.radicale-container.domain = userConfig.domain;
  services.radicale-container.subdomain = "calendar";
  services.radicale-container.enableGit = true;
  services.userconfig.user = userConfig.remoteUsername;
  services.userconfig.sshKeys = sshKeys;
  services.nginx-config.domain = userConfig.domain;
  services.nginx-config.email = userConfig.acmeEmail;
  services.nginx-config.webrootSubdomain = "www";
  services.nginx-config.staging = true;
  services.gitea-container.enable = true;
  services.gitea-container.subdomain = "gitea";
  services.gitea-container.domain = userConfig.domain;
  services.miniflux-container.enable = true;
  services.miniflux-container.subdomain = "rss";
  services.miniflux-container.domain = userConfig.domain;
  services.woodpecker-config.enable = true;
  services.woodpecker-config.domain = userConfig.domain;
  # A small pun here: we assume that the Gitea/Woodpecker username
  # is the same as the remote username.
  services.woodpecker-config.admin-users = [userConfig.remoteUsername];
  services.grafana-container.enable = true;
  services.grafana-container.domain = userConfig.domain;
  services.grafana-container.prometheusUrl = "http://${prometheusCfg.containerAddress}:${toString prometheusCfg.port}";
  services.prometheus-container.enable = true;
  services.prometheus-container.domain-exporter-domains = [userConfig.domain];
  services.puregym-container.enable = true;
  services.puregym-container.domain = userConfig.domain;
  services.puregym-container.subdomain = "puregym";
  services.apps-config.enable = true;
  services.apps-config.subdomain = "apps";
  services.apps-config.domain = userConfig.domain;
  # services.whisper-config.domain = userConfig.domain;
  # services.whisper-config.subdomain = "whisper";
  services.syncthing-container.enable = true;
  services.robocop-container.enable = true;
  services.robocop-container.subdomain = "robocop";
  services.robocop-container.domain = userConfig.domain;

  services.json-secrets.enable = true;

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
