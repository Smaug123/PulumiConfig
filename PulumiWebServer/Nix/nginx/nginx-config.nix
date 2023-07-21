{
  pkgs,
  lib,
  config,
  ...
}: {
  options = {
    services.nginx-config = {
      domain = lib.mkOption {
        type = lib.types.str;
        example = "example.com";
        description = lib.mdDoc "Domain to configure";
      };
      webrootSubdomain = lib.mkOption {
        type = lib.types.str;
        default = "www";
        description = lib.mdDoc "Global redirect";
      };
      email = lib.mkOption {
        type = lib.types.str;
        example = "admin@example.com";
        description = lib.mdDoc "Email address to use when registering with Let's Encrypt";
      };
      staging = lib.mkOption {
        type = lib.types.bool;
        default = "true";
        description = lib.mdDoc "Whether to use the staging Let's Encrypt instance";
      };
    };
  };

  config = {
    security.acme.acceptTerms = true;
    security.acme.defaults.email = config.services.nginx-config.email;
    security.acme.certs = {
      "${config.services.nginx-config.domain}" = {
        server =
          if config.services.nginx-config.staging
          then "https://acme-staging-v02.api.letsencrypt.org/directory"
          else "https://acme-v02.api.letsencrypt.org/directory";
      };
    };

    networking.firewall.allowedTCPPorts = [
      80 # required for the ACME challenge
      443
    ];

    users.users."nginx".extraGroups = [config.users.groups.keys.name];

    services.nginx = {
      enable = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      recommendedProxySettings = true;

      virtualHosts."${config.services.nginx-config.domain}" = {
        globalRedirect = "${config.services.nginx-config.webrootSubdomain}.${config.services.nginx-config.domain}";
        addSSL = true;
        enableACME = true;
        root = "/preserve/www/html";
      };

      virtualHosts."${config.services.nginx-config.webrootSubdomain}.${config.services.nginx-config.domain}" = {
        addSSL = true;
        enableACME = true;
        root = "/preserve/www/html";
        extraConfig = ''
          location ~* \.(?:ico|css|js|gif|jpe?g|png|woff2)$ {
              expires 30d;
              add_header Pragma public;
              add_header Cache-Control "public";
          }
        '';
      };
    };
  };
}
