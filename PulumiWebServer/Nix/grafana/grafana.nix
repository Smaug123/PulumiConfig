{
  config,
  pkgs,
  lib,
  ...
}: {
  options = {
    services.grafana-config = {
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
  };

  config = {
    services.nginx.virtualHosts."${config.services.grafana-config.subdomain}.${config.services.grafana-config.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.grafana-config.port}/";
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
          domain = "${config.services.grafana-config.subdomain}.${config.services.grafana-config.domain}";
          http_port = config.services.grafana-config.port;
          http_addr = "127.0.0.1";
          root_url = "https://${config.services.grafana-config.subdomain}.${config.services.grafana-config.domain}";
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
                name = "prometheus ${config.services.grafana-config.domain}";
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
