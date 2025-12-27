{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.woodpecker-config;
in {
  options.services.woodpecker-config = {
    enable = lib.mkEnableOption "Woodpecker CI server";
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
    agent-subdomain = lib.mkOption {
      type = lib.types.str;
      default = "woodpecker-agent";
      description = lib.mdDoc "Subdomain to open for Woodpecker agent gRPC";
    };
    port = lib.mkOption {
      type = lib.types.port;
      description = lib.mdDoc "Woodpecker localhost port";
      default = 9001;
    };
    grpc-port = lib.mkOption {
      type = lib.types.port;
      description = lib.mdDoc "Woodpecker server-agent communication port";
      default = 9010;
    };
    admin-users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = lib.mdDoc "List of admin usernames within the Woodpecker instance";
      default = [];
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = {
      "gitea_woodpecker_oauth_id" = {owner = "gitea";};
      "gitea_woodpecker_secret" = {owner = "gitea";};
      "woodpecker_agent_secret" = {owner = "gitea";};
    };

    services.woodpecker-server = {
      enable = true;
      environment = {
        WOODPECKER_HOST = "https://${cfg.subdomain}.${cfg.domain}";
        WOODPECKER_SERVER_ADDR = "localhost:${toString cfg.port}";
        WOODPECKER_LOG_LEVEL = "debug";
        WOODPECKER_GITEA = "true";
        WOODPECKER_GITEA_URL = "https://${config.services.gitea-config.subdomain}.${config.services.gitea-config.domain}";
        WOODPECKER_ADMIN = builtins.concatStringsSep "," cfg.admin-users;
        WOODPECKER_GRPC_ADDR = "localhost:${toString cfg.grpc-port}";
      };
      environmentFile = "/preserve/woodpecker/woodpecker-combined-secrets.txt";
    };

    services.woodpecker-agents = {
      agents = {
        docker-agent = {
          enable = true;
          extraGroups = ["docker"];
          environment = {
            WOODPECKER_SERVER = "localhost:${toString cfg.grpc-port}";
            WOODPECKER_BACKEND = "docker";
          };
          environmentFile = ["/preserve/woodpecker/woodpecker-combined-secrets.txt"];
        };
      };
    };

    systemd.services.woodpecker-secret = {
      description = "ensure woodpecker secrets are in place";
      wantedBy = ["multi-user.target" "woodpecker-server.service" "woodpecker-agent-docker-agent.service"];
      before = ["woodpecker-server.service" "woodpecker-agent-docker-agent.service"];
      script = builtins.readFile ./secrets.sh;
      serviceConfig = {
        Restart = "no";
        Type = "oneshot";
        User = "root";
      };
      environment = {
        OPENSSL = "${pkgs.openssl}/bin/openssl";
      };
    };

    services.nginx.virtualHosts."${cfg.subdomain}.${cfg.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString cfg.port}/";
        recommendedProxySettings = true;
        extraConfig = ''
          proxy_redirect off;
          proxy_http_version 1.1;
          proxy_buffering off;
          proxy_set_header X-Forwarded-For $remote_addr;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };
    };

    services.nginx.virtualHosts."${cfg.agent-subdomain}.${cfg.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        extraConfig = ''
          grpc_pass grpc://127.0.0.1:${toString cfg.grpc-port};
        '';
      };
    };
  };
}
