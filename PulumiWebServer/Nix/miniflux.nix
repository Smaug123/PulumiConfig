{
  config,
  pkgs,
  lib,
  ...
}: {
  options = {
    services.miniflux-config = {
      domain = lib.mkOption {
        type = lib.types.str;
        example = "example.com";
        description = lib.mdDoc "Top-level domain to configure";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        example = "rss";
        description = lib.mdDoc "Subdomain in which to put Gitea";
      };
      port = lib.mkOption {
        type = lib.types.port;
        description = lib.mdDoc "Gitea localhost port";
        default = 8080;
      };
    };
  };
  config = {
    users.users."miniflux".extraGroups = [config.users.groups.keys.name];
    services.miniflux = {
      enable = true;
      adminCredentialsFile = "/run/secrets/miniflux_admin_password";
    };

    services.nginx.virtualHosts."${config.services.miniflux-config.subdomain}.${config.services.miniflux-config.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString config.services.miniflux-config.port}/";
      };
    };
  };
}
