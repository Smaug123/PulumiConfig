{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.grafana-config;
in {
  options.services.grafana-config = {
    enable = lib.mkEnableOption "Grafana monitoring dashboard";
    domain = lib.mkOption {
      type = lib.types.str;
      example = "example.com";
      description = lib.mdDoc "Top-level domain to configure";
    };
    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "grafana";
      description = lib.mdDoc "Subdomain in which to put Grafana";
    };
    port = lib.mkOption {
      type = lib.types.port;
      description = lib.mdDoc "Grafana localhost port";
      default = 2342;
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = {
      "grafana_admin_password" = {owner = "grafana";};
      "grafana_secret_key" = {owner = "grafana";};
    };

    services.nginx.virtualHosts."${cfg.subdomain}.${cfg.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}/";
        proxyWebsockets = true;
      };
    };

    environment.etc."grafana-dashboards/node.json" = {
      source = ./node.json;
      group = "grafana";
      user = "grafana";
      mode = "0440";
    };

    services.grafana = {
      enable = true;
      settings = {
        server = {
          domain = "${cfg.subdomain}.${cfg.domain}";
          http_port = cfg.port;
          http_addr = "127.0.0.1";
          root_url = "https://${cfg.subdomain}.${cfg.domain}";
        };
        security = {
          disable_initial_admin_creation = false;
          admin_user = "admin";
          admin_password = "\$__file{/run/secrets/grafana_admin_password}";
          secret_key = "\$__file{/run/secrets/grafana_secret_key}";
          disable_gravatar = true;
          cookie_secure = true;
        };
        users = {
          allow_sign_up = false;
        };
      };
      provision = {
        enable = true;
        datasources = {
          settings = {
            datasources = [
              {
                name = "prometheus ${cfg.domain}";
                type = "prometheus";
                url = "http://127.0.0.1:${toString config.services.prometheus-config.port}";
                access = "proxy";
              }
            ];
          };
        };
        dashboards = {
          settings = {
            apiVersion = 1;
            providers = [
              {
                name = "default";
                options.path = "/etc/grafana-dashboards";
              }
            ];
          };
        };
      };
    };
  };
}
