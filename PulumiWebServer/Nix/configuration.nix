{nixpkgs, ...}: let
  lib = nixpkgs.lib;
  userConfig = lib.importJSON ./config.json;
  sshKeys = lib.importJSON ./ssh-keys.json;
in {
  imports = [
    ./sops.nix
    ./radicale/radicale-config.nix
    ./gitea/gitea-config.nix
    ./miniflux/miniflux.nix
    ./userconfig.nix
    ./nginx/nginx-config.nix
    ./woodpecker/woodpecker.nix
    ./prometheus/prometheus.nix
    ./grafana/grafana.nix
    # generated at runtime by nixos-infect and copied here
    ./hardware-configuration.nix
    ./networking.nix
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
  services.grafana-config.domain = userConfig.domain;
  services.prometheus-config.domain-exporter-domains = [userConfig.domain];

  system.stateVersion = "23.05";

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;
  networking.hostName = userConfig.name;
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = sshKeys;

  virtualisation.docker.enable = true;
  users.extraGroups.docker.members = [userConfig.remoteUsername];
}
