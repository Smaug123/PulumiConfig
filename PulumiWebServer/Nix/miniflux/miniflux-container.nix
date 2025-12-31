{
  config,
  pkgs,
  lib,
  primaryInterface,
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

    # NAT for container outbound access (required for fetching RSS feeds)
    networking.nat = {
      enable = true;
      internalInterfaces = ["ve-miniflux"];
      externalInterface = primaryInterface;
    };

    # Allow container to connect to PostgreSQL on the host
    networking.firewall.interfaces."ve-miniflux".allowedTCPPorts = [5432];

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
        listen_addresses = lib.mkForce "0.0.0.0";
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
      after = ["postgresql.service" "sops-nix.service"];
      requires = ["postgresql.service" "sops-nix.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Escape single quotes for SQL (double them)
        PW=$(cat /run/secrets/miniflux_db_password | ${pkgs.gnused}/bin/sed "s/'/''''/g")
        ${pkgs.sudo}/bin/sudo -u postgres ${pkgs.postgresql}/bin/psql -c "ALTER USER miniflux WITH PASSWORD '$PW';"
      '';
    };

    # Generate DATABASE_URL environment file for the container
    systemd.services.miniflux-env-file = {
      description = "Generate miniflux DATABASE_URL environment file";
      after = ["sops-nix.service"];
      requires = ["sops-nix.service"];
      wantedBy = ["multi-user.target"];
      before = ["container@miniflux.service"];
      requiredBy = ["container@miniflux.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "miniflux";
        RuntimeDirectoryMode = "0750";
      };
      script = ''
        # Escape for libpq key-value format: backslashes first, then single quotes
        PW=$(cat /run/secrets/miniflux_db_password | ${pkgs.gnused}/bin/sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g")
        # Quote the entire value for systemd EnvironmentFile parsing
        echo "DATABASE_URL=\"host=${hostAddress} dbname=miniflux user=miniflux password='$PW' sslmode=disable\"" > /run/miniflux/env
        chown miniflux:miniflux /run/miniflux/env
        chmod 0400 /run/miniflux/env
      '';
    };

    # Ensure the container waits for database password and env file
    systemd.services."container@miniflux" = {
      after = ["miniflux-db-password.service" "miniflux-env-file.service"];
      wants = ["miniflux-db-password.service" "miniflux-env-file.service"];
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
        "/run/miniflux/env" = {
          hostPath = "/run/miniflux/env";
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

        # Network configuration: use the host as the default gateway for outbound traffic
        networking.defaultGateway = hostAddress;

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

        # Use EnvironmentFile for DATABASE_URL (written by host's miniflux-env-file service)
        systemd.services.miniflux.serviceConfig = {
          EnvironmentFile = lib.mkForce "/run/miniflux/env";
          # Disable DynamicUser so we use the static miniflux user (uid 993) that owns the secrets
          DynamicUser = lib.mkForce false;
        };

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
