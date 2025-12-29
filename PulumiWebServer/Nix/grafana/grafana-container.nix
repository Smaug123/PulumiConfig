{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.grafana-container;
  # Container networking
  hostAddress = "192.168.100.1";
  containerAddress = "192.168.100.7";
  prometheusAddress = "192.168.100.6";
  # Data directory for Grafana
  dataDir = "/preserve/grafana";
in {
  options.services.grafana-container = {
    enable = lib.mkEnableOption "Grafana monitoring dashboard (containerised)";
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
      description = lib.mdDoc "Grafana port inside container";
      default = 2342;
    };
  };

  config = lib.mkIf cfg.enable {
    # Create grafana user/group on the host with explicit UIDs matching the container.
    users.users.grafana = {
      uid = 196;
      isSystemUser = true;
      group = "grafana";
    };
    users.groups.grafana.gid = 989;

    # Secrets are decrypted on the host and bind-mounted into the container.
    sops.secrets = {
      "grafana_admin_password" = {
        owner = "grafana";
        group = "grafana";
      };
      "grafana_secret_key" = {
        owner = "grafana";
        group = "grafana";
      };
    };

    # Ensure the data directory exists and is owned by grafana
    systemd.tmpfiles.rules = [
      "d ${dataDir} 0750 grafana grafana -"
      "Z ${dataDir} - grafana grafana -"
    ];

    # Dashboard files on host - bind-mounted into container
    environment.etc."grafana-dashboards/node.json" = {
      source = ./node.json;
      group = "grafana";
      user = "grafana";
      mode = "0440";
    };

    containers.grafana = {
      autoStart = true;
      privateNetwork = true;
      hostAddress = hostAddress;
      localAddress = containerAddress;

      bindMounts = {
        "${dataDir}" = {
          hostPath = dataDir;
          isReadOnly = false;
        };
        "/run/secrets/grafana_admin_password" = {
          hostPath = "/run/secrets/grafana_admin_password";
          isReadOnly = true;
        };
        "/run/secrets/grafana_secret_key" = {
          hostPath = "/run/secrets/grafana_secret_key";
          isReadOnly = true;
        };
        "/etc/grafana-dashboards" = {
          hostPath = "/etc/grafana-dashboards";
          isReadOnly = true;
        };
      };

      config = {
        config,
        pkgs,
        ...
      }: {
        system.stateVersion = "23.05";

        # The grafana user needs to exist in the container with matching UID/GID
        users.users.grafana = {
          uid = 196;
          isSystemUser = true;
          group = "grafana";
        };
        users.groups.grafana.gid = 989;

        services.grafana = {
          enable = true;
          dataDir = dataDir;
          settings = {
            server = {
              domain = "${cfg.subdomain}.${cfg.domain}";
              http_port = cfg.port;
              http_addr = "0.0.0.0";
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
                    # Prometheus is in another container (default port 9002)
                    url = "http://${prometheusAddress}:9002";
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

        # Allow inbound traffic on grafana port
        networking.firewall.allowedTCPPorts = [cfg.port];
      };
    };

    # nginx on the host proxies to the container
    services.nginx.virtualHosts."${cfg.subdomain}.${cfg.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://${containerAddress}:${toString cfg.port}/";
        proxyWebsockets = true;
      };
    };
  };
}
