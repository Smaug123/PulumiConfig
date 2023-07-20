{
  config,
  pkgs,
  lib,
  ...
}: {
  options = {
    services.woodpecker-config = {
      domain = lib.mkOption {
        type = lib.types.str;
        example = "example.com";
        description = lib.mdDoc "Top-level domain to configure";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        default = "woodpecker";
        description = lib.mdDoc "Subdomain in which to put Woodpecker";
      };
      port = lib.mkOption {
        type = lib.types.port;
        description = lib.mdDoc "Woodpecker localhost port";
        default = 9001;
      };
    };
  };

  config.users.users."woodpecker" = {
    isSystemUser = true;
    group = "woodpecker";
    extraGroups = ["docker"];
  };
  config.users.groups."woodpecker" = {};

  config.environment.etc = {
    "woodpecker.yaml" = {
      text = builtins.replaceStrings ["%%WOODPECKER_PORT%%" "%%WOODPECKER_SUBDOMAIN%%" "%%WOODPECKER_DOMAIN%%" "%%GITEA_SUBDOMAIN%%"] [(toString config.services.woodpecker-config.port) config.services.woodpecker-config.subdomain config.services.woodpecker-config.domain config.services.gitea-config.subdomain] (builtins.readFile ./woodpecker/compose.yaml);
      mode = "0440";
      user = "woodpecker";
    };
  };

  config.systemd.services.start-woodpecker = {
    description = "start-woodpecker";
    wantedBy = ["multi-user.target"];
    path = [pkgs.docker];
    script = builtins.readFile ./woodpecker/start.sh;
    serviceConfig = {
      Restart = "on-failure";
      Type = "exec";
      User = "woodpecker";
      Group = "woodpecker";
    };
    environment = {
      DOCKER = "${pkgs.docker}/bin/docker";
      OPENSSL = "${pkgs.openssl}/bin/openssl";
    };
  };

  config = {
    services.nginx.virtualHosts."${config.services.woodpecker-config.subdomain}.${config.services.woodpecker-config.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString config.services.woodpecker-config.port}/";
      };
    };
  };
}
