{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.miniflux-config;
in {
  options.services.miniflux-config = {
    enable = lib.mkEnableOption "Miniflux RSS reader";
    domain = lib.mkOption {
      type = lib.types.str;
      example = "example.com";
      description = lib.mdDoc "Top-level domain to configure";
    };
    subdomain = lib.mkOption {
      type = lib.types.str;
      example = "rss";
      description = lib.mdDoc "Subdomain in which to put Miniflux";
    };
    port = lib.mkOption {
      type = lib.types.port;
      description = lib.mdDoc "Miniflux localhost port";
      default = 8080;
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = {
      "miniflux_admin_password" = {owner = "miniflux";};
    };
    users.users."miniflux".extraGroups = [config.users.groups.keys.name];
    services.miniflux = {
      enable = true;
      adminCredentialsFile = "/run/secrets/miniflux_admin_password";
    };

    services.nginx.virtualHosts."${cfg.subdomain}.${cfg.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString cfg.port}/";
      };
    };
  };
}
