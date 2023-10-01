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
  };

  config.services.woodpecker-server = {
    enable = true;
    environment = {
      WOODPECKER_HOST = "https://${config.services.woodpecker-config.subdomain}.${config.services.woodpecker-config.domain}";
      WOODPECKER_SERVER_ADDR = "localhost:${toString config.services.woodpecker-config.port}";
      WOODPECKER_LOG_LEVEL = "debug";
      WOODPECKER_GITEA = "true";
      WOODPECKER_GITEA_URL = "https://${config.services.gitea-config.subdomain}.${config.services.gitea-config.domain}";
      WOODPECKER_ADMIN = builtins.concatStringsSep "," config.services.woodpecker-config.admin-users;
      WOODPECKER_GRPC_ADDR = "localhost:${toString config.services.woodpecker-config.grpc-port}";
    };
    environmentFile = "/preserve/woodpecker/woodpecker-combined-secrets.txt";
  };

  config.services.woodpecker-agents = {
    agents = {
      podman-agent = {
        enable = true;
        extraGroups = ["podman"];
        environment = {
          WOODPECKER_SERVER = "localhost:${toString config.services.woodpecker-config.grpc-port}";
          WOODPECKER_BACKEND = "docker";
          DOCKER_HOST = "unix:///run/podman/podman.sock";
        };
        environmentFile = ["/preserve/woodpecker/woodpecker-combined-secrets.txt"];
      };
    };
  };

  config.systemd.services.woodpecker-secret = {
    description = "ensure woodpecker secrets are in place";
    wantedBy = ["multi-user.target" "woodpecker-server.service" "woodpecker-agent-podman-agent.service"];
    before = ["woodpecker-server.service" "woodpecker-agent-podman-agent.service"];
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

  config.services.nginx.virtualHosts."${config.services.woodpecker-config.subdomain}.${config.services.woodpecker-config.domain}" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString config.services.woodpecker-config.port}/";
    };
  };

  config.services.nginx.virtualHosts."${config.services.woodpecker-config.agent-subdomain}.${config.services.woodpecker-config.domain}" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      extraConfig = ''
        grpc_pass grpc://127.0.0.1:${toString config.services.woodpecker-config.grpc-port};
      '';
    };
  };
}
