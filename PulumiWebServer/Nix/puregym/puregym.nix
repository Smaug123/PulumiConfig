{
  config,
  pkgs,
  lib,
  puregym-client,
  ...
}: let
  cfg = config.services.puregym-config;
in {
  options.services.puregym-config = {
    enable = lib.mkEnableOption "PureGym attendance tracking";
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
      description = lib.mdDoc "PureGym localhost port to be forwarded";
      default = 1735;
    };
  };

  config = lib.mkIf cfg.enable {
    users.users."puregym".extraGroups = [config.users.groups.keys.name];
    users.users."puregym".group = "puregym";
    users.groups.puregym = {};
    users.users."puregym".isSystemUser = true;

    sops.secrets = {
      "puregym_email" = {owner = "puregym";};
      "puregym_pin" = {owner = "puregym";};
    };

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
      wants = ["puregym-refresh-auth.target"];
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

    services.nginx.virtualHosts."${cfg.subdomain}.${cfg.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString cfg.port}/";
      };
    };

    services.prometheus.scrapeConfigs = [
      {
        job_name = "gym-fullness";
        static_configs = [
          {
            targets = ["localhost:${toString cfg.port}"];
          }
        ];
        params = {gym_id = ["19"];};
        metrics_path = "/fullness-prometheus";
        scrape_interval = "5m";
      }
    ];

    environment.etc."grafana-dashboards/puregym.json" = {
      source = ../grafana/puregym.json;
      group = "grafana";
      user = "grafana";
      mode = "0440";
    };
  };
}
