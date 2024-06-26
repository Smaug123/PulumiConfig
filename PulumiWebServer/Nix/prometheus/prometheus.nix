{
  config,
  pkgs,
  lib,
  ...
}: {
  options = {
    services.prometheus-config = {
      port = lib.mkOption {
        type = lib.types.port;
        description = lib.mdDoc "Prometheus localhost port";
        default = 9002;
      };
      node-exporter-port = lib.mkOption {
        type = lib.types.port;
        description = lib.mdDoc "Localhost port for node exporter";
        default = 9003;
      };
      domain-exporter-domains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = lib.mdDoc "Paths to be interpolated into the domain-exporter config.";
        example = "example.com";
      };
    };
  };

  config = {
    # For the domain exporter
    environment.etc."domain-exporter/domains.yaml" = {
      text = let
        interp = builtins.concatStringsSep "\", \"" config.services.prometheus-config.domain-exporter-domains;
      in
        builtins.replaceStrings ["%%DOMAINS%%"] [interp] (builtins.readFile ./domains.yaml);
    };

    services.prometheus = {
      enable = true;
      port = config.services.prometheus-config.port;
      retentionTime = "60d";
      exporters = {
        node = {
          enable = true;
          enabledCollectors = ["systemd"];
          port = config.services.prometheus-config.node-exporter-port;
        };
        nginx = {
          enable = true;
        };
        domain = {
          enable = true;
          extraFlags = ["--config=/etc/domain-exporter/domains.yaml"];
        };
      };

      scrapeConfigs = [
        {
          job_name = "gym-fullness";
          static_configs = [
            {
              # Gym 19 is London Oval
              targets = ["localhost:${toString config.services.puregym-config.port}"];
            }
          ];
          params = {gym_id = ["19"];};
          metrics_path = "/fullness-prometheus";
          scrape_interval = "5m";
        }
        {
          job_name = "node";
          static_configs = [
            {
              targets = ["localhost:${toString config.services.prometheus.exporters.node.port}"];
            }
          ];
        }
        {
          job_name = "nginx";
          static_configs = [
            {
              # Non-configurable magic port used for nginx status
              targets = ["localhost:9113"];
            }
          ];
        }
        {
          job_name = "domain";
          static_configs = [
            {
              # Non-configurable magic port used for domain exporter
              targets = ["localhost:9222"];
            }
          ];
        }
      ];
    };
  };
}
