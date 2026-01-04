{
  config,
  pkgs,
  lib,
  puregym-client,
  primaryInterface,
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
    # These are historical details: the UID/GID that were auto-allocated before we moved to containers.
    users.users.puregym = {
      uid = 990;
      isSystemUser = true;
      group = "puregym";
    };
    users.groups.puregym.gid = 986;

    # NAT for container outbound access (required for PureGym API calls)
    networking.nat = {
      enable = true;
      internalInterfaces = ["ve-puregym"];
      externalInterface = primaryInterface;
    };

    # Secrets are managed by json-secrets and bind-mounted into the container.

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
        # Mount the entire nix store so the .NET runtime can access all its dependencies.
        # Unlike Rust binaries which are statically linked, .NET apps have many runtime
        # dependencies (ICU, CoreCLR, etc.) that live in separate store paths.
        "/nix/store" = {
          hostPath = "/nix/store";
          isReadOnly = true;
        };
      };

      config = {
        config,
        pkgs,
        ...
      }: {
        system.stateVersion = "23.05";

        # Network configuration: use the host as the default gateway for outbound traffic
        networking.defaultGateway = hostAddress;

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
          after = ["network-online.target"];
          wants = ["network-online.target"];
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
          requires = ["puregym-refresh-auth.service"];
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

    # Grafana dashboard - stays on host since Grafana reads from /etc
    environment.etc."grafana-dashboards/puregym.json" = {
      source = ../grafana/puregym.json;
      group = "grafana";
      user = "grafana";
      mode = "0440";
    };

    # Prometheus scrape config for PureGym metrics
    services.prometheus-container.extraScrapeConfigs = [
      {
        job_name = "gym-fullness";
        static_configs = [
          {
            targets = ["${containerAddress}:${toString cfg.port}"];
          }
        ];
        params = {gym_id = ["19"];};
        metrics_path = "/fullness-prometheus";
        scrape_interval = "5m";
      }
    ];
  };
}
