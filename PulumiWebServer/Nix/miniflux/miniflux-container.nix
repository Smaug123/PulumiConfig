{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.miniflux-container;
  # Container networking
  hostAddress = "192.168.100.1";
  containerAddress = "192.168.100.9";
in {
  options.services.miniflux-container = {
    enable = lib.mkEnableOption "Miniflux RSS reader (containerised)";
    domain = lib.mkOption {
      type = lib.types.str;
      example = "example.com";
      description = lib.mdDoc "Top-level domain to configure";
    };
    subdomain = lib.mkOption {
      type = lib.types.str;
      example = "rss";
      description = lib.mdDoc "Subdomain in which to put Miniflux";
    };
    port = lib.mkOption {
      type = lib.types.port;
      description = lib.mdDoc "Miniflux port inside container";
      default = 8080;
    };
  };

  config = lib.mkIf cfg.enable {
    # Create miniflux user/group on the host with explicit UIDs matching the container.
    users.users.miniflux = {
      uid = 993;
      isSystemUser = true;
      group = "miniflux";
    };
    users.groups.miniflux.gid = 991;

    # Secrets are decrypted on the host and bind-mounted into the container.
    sops.secrets = {
      "miniflux_admin_password" = {
        owner = "miniflux";
        group = "miniflux";
      };
      "miniflux_db_password" = {
        owner = "miniflux";
        group = "miniflux";
      };
    };

    # PostgreSQL on host needs to listen on bridge and allow miniflux connections
    services.postgresql = {
      enable = true;
      enableTCPIP = true;
      # Listen on bridge interface for container access
      settings = {
        listen_addresses = lib.mkForce "localhost,${hostAddress}";
      };
      authentication = lib.mkAfter ''
        # Allow miniflux container to connect via TCP with password
        host miniflux miniflux ${containerAddress}/32 md5
      '';
      ensureDatabases = ["miniflux"];
      ensureUsers = [
        {
          name = "miniflux";
          ensureDBOwnership = true;
        }
      ];
    };

    # Set miniflux password after PostgreSQL starts
    systemd.services.miniflux-db-password = {
      description = "Set miniflux PostgreSQL password";
      after = ["postgresql.service"];
      requires = ["postgresql.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.postgresql}/bin/psql -c "ALTER USER miniflux WITH PASSWORD '$(cat /run/secrets/miniflux_db_password)';"
      '';
    };

    containers.miniflux = {
      autoStart = true;
      privateNetwork = true;
      hostAddress = hostAddress;
      localAddress = containerAddress;

      bindMounts = {
        "/run/secrets/miniflux_admin_password" = {
          hostPath = "/run/secrets/miniflux_admin_password";
          isReadOnly = true;
        };
        "/run/secrets/miniflux_db_password" = {
          hostPath = "/run/secrets/miniflux_db_password";
          isReadOnly = true;
        };
      };

      config = {
        config,
        pkgs,
        lib,
        ...
      }: {
        system.stateVersion = "23.05";

        # The miniflux user needs to exist in the container with matching UID/GID
        users.users.miniflux = {
          uid = 993;
          isSystemUser = true;
          group = "miniflux";
        };
        users.groups.miniflux.gid = 991;

        services.miniflux = {
          enable = true;
          createDatabaseLocally = false;
          adminCredentialsFile = "/run/secrets/miniflux_admin_password";
          config = {
            LISTEN_ADDR = "0.0.0.0:${toString cfg.port}";
          };
        };

        # Override miniflux service to inject DATABASE_URL with password from secret
        systemd.services.miniflux.serviceConfig.ExecStartPre = lib.mkBefore [
          "+${pkgs.writeShellScript "miniflux-db-env" ''
            DB_PASS=$(cat /run/secrets/miniflux_db_password)
            echo "DATABASE_URL=postgres://miniflux:$DB_PASS@${hostAddress}/miniflux?sslmode=disable" > /run/miniflux-db-env
            chmod 400 /run/miniflux-db-env
            chown miniflux:miniflux /run/miniflux-db-env
          ''}"
        ];
        systemd.services.miniflux.serviceConfig.EnvironmentFile = lib.mkForce ["/run/miniflux-db-env"];

        # Allow inbound traffic on miniflux port
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
