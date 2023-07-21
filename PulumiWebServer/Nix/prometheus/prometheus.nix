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
    };
  };

  config = {
    services.prometheus = {
      enable = true;
      port = config.services.prometheus-config.port;
      exporters = {
        node = {
          enable = true;
          enabledCollectors = ["systemd"];
          port = config.services.prometheus-config.node-exporter-port;
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
      ];
    };
  };
}
