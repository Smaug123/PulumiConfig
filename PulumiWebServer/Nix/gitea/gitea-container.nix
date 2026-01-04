{
  config,
  pkgs,
  lib,
  primaryInterface,
  ...
}: let
  cfg = config.services.gitea-container;
  # Container networking
  hostAddress = "192.168.100.1";
  containerAddress = "192.168.100.3";
  # Data directory for Gitea
  dataDir = "/preserve/gitea/data";
in {
  options.services.gitea-container = {
    enable = lib.mkEnableOption "Gitea git server (containerised)";
    domain = lib.mkOption {
      type = lib.types.str;
      example = "example.com";
      description = lib.mdDoc "Top-level domain to configure";
    };
    subdomain = lib.mkOption {
      type = lib.types.str;
      example = "gitea";
      description = lib.mdDoc "Subdomain in which to put Gitea";
    };
    port = lib.mkOption {
      type = lib.types.port;
      description = lib.mdDoc "Gitea port inside container";
      default = 3001;
    };
    woodpecker-oauth-redirect = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://woodpecker.example.com/authorize";
      description = lib.mdDoc "If set, creates a Woodpecker OAuth2 application with this redirect URI. Credentials are written to /preserve/gitea/woodpecker-oauth-*.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create gitea user/group on the host with explicit UIDs matching the container.
    # These match what the NixOS gitea module auto-allocates in the container.
    users.users.gitea = {
      uid = 994;
      isSystemUser = true;
      group = "gitea";
    };
    users.groups.gitea.gid = 992;

    # NAT for container outbound access (required for webhooks, federation, etc.)
    networking.nat = {
      enable = true;
      internalInterfaces = ["ve-gitea"];
      externalInterface = primaryInterface;
    };

    # Secrets are managed by json-secrets and bind-mounted into the container.

    # Ensure the data directory exists and is owned by gitea
    systemd.tmpfiles.rules = [
      "d ${dataDir} 0750 gitea gitea -"
      "Z ${dataDir} - gitea gitea -"
    ];

    containers.gitea = {
      autoStart = true;
      privateNetwork = true;
      hostAddress = hostAddress;
      localAddress = containerAddress;

      bindMounts = {
        "${dataDir}" = {
          hostPath = dataDir;
          isReadOnly = false;
        };
        "/run/secrets/gitea_admin_password" = {
          hostPath = "/run/secrets/gitea_admin_password";
          isReadOnly = true;
        };
        "/run/secrets/gitea_admin_username" = {
          hostPath = "/run/secrets/gitea_admin_username";
          isReadOnly = true;
        };
        "/run/secrets/gitea_admin_email" = {
          hostPath = "/run/secrets/gitea_admin_email";
          isReadOnly = true;
        };
        # robots.txt to disallow crawling
        "/var/lib/gitea-robots/robots.txt" = {
          hostPath = "${./robots.txt}";
          isReadOnly = true;
        };
      };

      config = {
        config,
        pkgs,
        lib,
        ...
      }: let
        docutils = pkgs.python311.withPackages (ps:
          with ps; [
            docutils
            pygments
          ]);
      in {
        system.stateVersion = "23.05";

        # Network configuration: use the host as the default gateway for outbound traffic
        networking.defaultGateway = hostAddress;

        # Explicitly create gitea user/group with UIDs matching the host
        users.users.gitea = {
          uid = 994;
          isSystemUser = true;
          group = "gitea";
          home = dataDir;
        };
        users.groups.gitea.gid = 992;

        services.gitea = {
          enable = true;
          appName = "Gitea";
          lfs.enable = true;
          stateDir = dataDir;
          database = {
            type = "sqlite3";
            path = "${dataDir}/gitea.db";
          };
          settings = {
            mailer = {
              ENABLED = true;
              FROM = "gitea@" + cfg.domain;
            };
            server = {
              ROOT_URL = "https://${cfg.subdomain}.${cfg.domain}/";
              HTTP_PORT = cfg.port;
              HTTP_ADDR = "0.0.0.0";
              DOMAIN = "${cfg.subdomain}.${cfg.domain}";
            };
            service = {
              REGISTER_EMAIL_CONFIRM = true;
              DISABLE_REGISTRATION = true;
              COOKIE_SECURE = true;
            };
            webhook = {
              ALLOWED_HOST_LIST = "external,loopback";
            };
            "markup.restructuredtext" = {
              ENABLED = true;
              FILE_EXTENSIONS = ".rst";
              RENDER_COMMAND = ''${docutils}/bin/rst2html.py'';
              IS_INPUT_FILE = false;
            };
            repository = {
              DISABLE_DOWNLOAD_SOURCE_ARCHIVES = true;
            };
          };
        };

        # Copy robots.txt to custom public directory
        systemd.services.gitea.preStart = lib.mkAfter ''
          mkdir -p ${dataDir}/custom/public
          cp /var/lib/gitea-robots/robots.txt ${dataDir}/custom/public/robots.txt
        '';

        # The Gitea module does not allow adding users declaratively
        systemd.services.gitea-add-user = {
          description = "gitea-add-user";
          after = ["gitea.service"];
          requires = ["gitea.service"];
          wantedBy = ["multi-user.target"];
          path = [pkgs.gitea pkgs.curl pkgs.jq];
          script = builtins.readFile ./add-user.sh;
          serviceConfig = {
            Restart = "no";
            Type = "oneshot";
            User = "gitea";
            Group = "gitea";
            WorkingDirectory = dataDir;
          };
          environment =
            {
              GITEA_WORK_DIR = dataDir;
              GITEA = "${pkgs.gitea}/bin/gitea";
              GITEA_PORT = toString cfg.port;
            }
            // lib.optionalAttrs (cfg.woodpecker-oauth-redirect != null) {
              WOODPECKER_OAUTH_REDIRECT = cfg.woodpecker-oauth-redirect;
            };
        };

        # Allow inbound traffic on gitea port
        networking.firewall.allowedTCPPorts = [cfg.port];
      };
    };

    # nginx on the host proxies to the container
    services.nginx.virtualHosts."${cfg.subdomain}.${cfg.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://${containerAddress}:${toString cfg.port}/";
      };
    };
  };
}
