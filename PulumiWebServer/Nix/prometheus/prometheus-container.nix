{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.prometheus-container;
  # Container networking
  hostAddress = "192.168.100.1";
  containerAddress = "192.168.100.6";
  # Data directory for Prometheus
  dataDir = "/preserve/prometheus";
in {
  options.services.prometheus-container = {
    enable = lib.mkEnableOption "Prometheus monitoring (containerised)";
    port = lib.mkOption {
      type = lib.types.port;
      description = lib.mdDoc "Prometheus port inside container";
      default = 9002;
    };
    node-exporter-port = lib.mkOption {
      type = lib.types.port;
      description = lib.mdDoc "Host port for node exporter";
      default = 9003;
    };
    domain-exporter-domains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = lib.mdDoc "Domains to be interpolated into the domain-exporter config.";
      example = ["example.com"];
    };
  };

  config = lib.mkIf cfg.enable {
    # Create prometheus user/group on the host with explicit UIDs matching the container.
    users.users.prometheus = {
      uid = 255;
      isSystemUser = true;
      group = "prometheus";
    };
    users.groups.prometheus.gid = 255;

    # Ensure the data directory exists and is owned by prometheus
    systemd.tmpfiles.rules = [
      "d ${dataDir} 0750 prometheus prometheus -"
      "Z ${dataDir} - prometheus prometheus -"
    ];

    # === EXPORTERS RUN ON HOST ===
    # They need access to host resources (systemd, nginx, etc.)

    # Domain exporter config file
    environment.etc."domain-exporter/domains.yaml" = {
      text = let
        interp = builtins.concatStringsSep "\", \"" cfg.domain-exporter-domains;
      in
        builtins.replaceStrings ["%%DOMAINS%%"] [interp] (builtins.readFile ./domains.yaml);
    };

    # Node exporter on host
    services.prometheus.exporters.node = {
      enable = true;
      enabledCollectors = ["systemd"];
      port = cfg.node-exporter-port;
      # Listen on bridge interface so container can reach it
      listenAddress = hostAddress;
    };

    # Nginx exporter on host
    services.prometheus.exporters.nginx = {
      enable = true;
      # Listen on bridge interface so container can reach it
      listenAddress = hostAddress;
    };

    # Domain exporter on host
    services.prometheus.exporters.domain = {
      enable = true;
      extraFlags = ["--config=/etc/domain-exporter/domains.yaml"];
      # Listen on bridge interface so container can reach it
      listenAddress = hostAddress;
    };

    # === PROMETHEUS SERVER IN CONTAINER ===

    containers.prometheus = {
      autoStart = true;
      privateNetwork = true;
      hostAddress = hostAddress;
      localAddress = containerAddress;

      bindMounts = {
        # Prometheus stateDir is relative to /var/lib/, so we mount to the actual path it uses
        "/var/lib/prometheus2" = {
          hostPath = dataDir;
          isReadOnly = false;
        };
      };

      config = {
        config,
        pkgs,
        ...
      }: {
        system.stateVersion = "23.05";

        # The prometheus user needs to exist in the container with matching UID/GID
        users.users.prometheus = {
          uid = 255;
          isSystemUser = true;
          group = "prometheus";
        };
        users.groups.prometheus.gid = 255;

        services.prometheus = {
          enable = true;
          port = cfg.port;
          listenAddress = "0.0.0.0";
          stateDir = "prometheus2";
          retentionTime = "60d";

          # Scrape exporters on the host via bridge IP
          scrapeConfigs = [
            {
              job_name = "node";
              static_configs = [
                {
                  targets = ["${hostAddress}:${toString cfg.node-exporter-port}"];
                }
              ];
            }
            {
              job_name = "nginx";
              static_configs = [
                {
                  # nginx exporter default port
                  targets = ["${hostAddress}:9113"];
                }
              ];
            }
            {
              job_name = "domain";
              static_configs = [
                {
                  # domain exporter default port
                  targets = ["${hostAddress}:9222"];
                }
              ];
            }
            {
              job_name = "gym-fullness";
              static_configs = [
                {
                  # PureGym container
                  targets = ["192.168.100.5:1735"];
                }
              ];
              params = {gym_id = ["19"];};
              metrics_path = "/fullness-prometheus";
              scrape_interval = "5m";
            }
          ];
        };

        # Allow inbound traffic on prometheus port
        networking.firewall.allowedTCPPorts = [cfg.port];
      };
    };
  };
}
