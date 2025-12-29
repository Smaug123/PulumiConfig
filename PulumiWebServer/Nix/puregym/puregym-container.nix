{
  config,
  pkgs,
  lib,
  puregym-client,
  ...
}: let
  cfg = config.services.puregym-container;
  # Container networking
  hostAddress = "192.168.100.1";
  containerAddress = "192.168.100.5";
in {
  options.services.puregym-container = {
    enable = lib.mkEnableOption "PureGym attendance tracking (containerised)";
    domain = lib.mkOption {
      type = lib.types.str;
      example = "example.com";
      description = lib.mdDoc "Top-level domain to configure";
    };
    subdomain = lib.mkOption {
      type = lib.types.str;
      example = "puregym";
      description = lib.mdDoc "Subdomain in which to put the PureGym server";
    };
    port = lib.mkOption {
      type = lib.types.port;
      description = lib.mdDoc "PureGym port inside container";
      default = 1735;
    };
  };

  config = lib.mkIf cfg.enable {
    # Create puregym user/group on the host with explicit UIDs matching the container.
    users.users.puregym = {
      uid = 990;
      isSystemUser = true;
      group = "puregym";
    };
    users.groups.puregym.gid = 986;

    # Secrets are decrypted on the host and bind-mounted into the container.
    sops.secrets = {
      "puregym_email" = {
        owner = "puregym";
        group = "puregym";
      };
      "puregym_pin" = {
        owner = "puregym";
        group = "puregym";
      };
    };

    containers.puregym = {
      autoStart = true;
      privateNetwork = true;
      hostAddress = hostAddress;
      localAddress = containerAddress;

      bindMounts = {
        "/run/secrets/puregym_email" = {
          hostPath = "/run/secrets/puregym_email";
          isReadOnly = true;
        };
        "/run/secrets/puregym_pin" = {
          hostPath = "/run/secrets/puregym_pin";
          isReadOnly = true;
        };
        # Bind-mount the puregym-client package from the host's nix store
        "${puregym-client}" = {
          hostPath = "${puregym-client}";
          isReadOnly = true;
        };
      };

      config = {
        config,
        pkgs,
        ...
      }: {
        system.stateVersion = "23.05";

        # The puregym user needs to exist in the container with matching UID/GID
        users.users.puregym = {
          uid = 990;
          isSystemUser = true;
          group = "puregym";
        };
        users.groups.puregym.gid = 986;

        systemd.services.puregym-refresh-auth = {
          description = "puregym-refresh-auth";
          wantedBy = ["multi-user.target"];
          path = [puregym-client];
          script = builtins.readFile ./refresh-auth.sh;
          serviceConfig = {
            Restart = "no";
            Type = "oneshot";
            User = "puregym";
            Group = "puregym";
          };
          environment = {
            PUREGYM = "${puregym-client}/bin/PureGym.App";
          };
        };

        systemd.timers.puregym-refresh-auth = {
          wantedBy = ["timers.target"];
          partOf = ["puregym-refresh-auth.service"];
          timerConfig = {
            OnCalendar = "monthly";
            Unit = "puregym-refresh-auth.service";
          };
        };

        systemd.services.puregym-server = {
          description = "puregym-server";
          wantedBy = ["multi-user.target"];
          wants = ["puregym-refresh-auth.service"];
          after = ["puregym-refresh-auth.service"];
          serviceConfig = {
            Restart = "always";
            Type = "exec";
            User = "puregym";
            Group = "puregym";
            ExecStart = "${pkgs.python3}/bin/python ${./puregym.py}";
          };
          environment = {
            PUREGYM_CLIENT = "${puregym-client}/bin/PureGym.App";
            PUREGYM_PORT = toString cfg.port;
          };
        };

        # Allow inbound traffic on puregym port
        networking.firewall.allowedTCPPorts = [cfg.port];
      };
    };

    # nginx on the host proxies to the container
    services.nginx.virtualHosts."${cfg.subdomain}.${cfg.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://${containerAddress}:${toString cfg.port}/";
      };
    };

    # Prometheus scrape config is now in prometheus-container.nix
    # since Prometheus runs in its own container

    # Grafana dashboard - stays on host since Grafana reads from /etc
    environment.etc."grafana-dashboards/puregym.json" = {
      source = ../grafana/puregym.json;
      group = "grafana";
      user = "grafana";
      mode = "0440";
    };
  };
}
