{
  config,
  pkgs,
  lib,
  puregym-client,
  ...
}: {
  options = {
    services.puregym-config = {
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
  };

  config = {
    users.users."puregym".extraGroups = [config.users.groups.keys.name];
    users.users."puregym".group = "puregym";
    users.groups.puregym = {};
    users.users."puregym".isSystemUser = true;

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
        PUREGYM_PORT = toString config.services.puregym-config.port;
      };
    };

    services.nginx.virtualHosts."${config.services.puregym-config.subdomain}.${config.services.puregym-config.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString config.services.puregym-config.port}/";
      };
    };
  };
}
