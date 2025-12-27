{
  config,
  pkgs,
  lib,
  robocop,
  ...
}: let
  cfg = config.services.robocop-config;
in {
  options.services.robocop-config = {
    enable = lib.mkEnableOption "Robocop server";
    domain = lib.mkOption {
      type = lib.types.str;
      example = "example.com";
      description = lib.mdDoc "Top-level domain to configure";
    };
    subdomain = lib.mkOption {
      type = lib.types.str;
      example = "robocop";
      description = lib.mdDoc "Subdomain in which to put the Robocop server";
    };
    port = lib.mkOption {
      type = lib.types.port;
      description = lib.mdDoc "Robocop localhost port to be forwarded";
      default = 8259;
    };
  };

  config = lib.mkIf cfg.enable {
    users.users."robocop".group = "robocop";
    users.groups.robocop = {};
    users.users."robocop".isSystemUser = true;

    systemd.services.robocop-server = {
      description = "robocop-server";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Restart = "always";
        Type = "simple";
        User = "robocop";
        Group = "robocop";
        ExecStart = "${robocop}/bin/robocop-server";
        Environment = "PORT=${toString cfg.port}";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;

        EnvironmentFile = "/etc/robocop/env";
      };
    };

    services.nginx.virtualHosts."${cfg.subdomain}.${cfg.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString cfg.port}/";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };
    };
  };
}
