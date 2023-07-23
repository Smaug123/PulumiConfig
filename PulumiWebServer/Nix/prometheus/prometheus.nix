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
        type = lib.types.string;
        description = lib.mdDoc "Paths to be interpolated into the domain-exporter config. To specify multiple, you'll have to give the JSON string delimiter and comma yourself.";
        example = "example.com";
      };
    };
  };

  config = {
    # For the domain exporter
    environment.etc."domain-exporter/domains.yaml" = {
      text = builtins.replaceStrings ["%%DOMAINS%%"] [config.services.prometheus-config.domain-exporter-domains] (builtins.readFile ./domains.yaml);
    };

    services.prometheus = {
      enable = true;
      port = config.services.prometheus-config.port;
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
