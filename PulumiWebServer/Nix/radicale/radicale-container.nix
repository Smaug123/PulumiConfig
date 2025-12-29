{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.services.radicale-container;
  filesystem_folder = "/preserve/radicale/data";
  # Container networking
  hostAddress = "192.168.100.1";
  containerAddress = "192.168.100.2";
in {
  options.services.radicale-container = {
    enable = lib.mkEnableOption "Radicale calendar server (containerised)";
    domain = lib.mkOption {
      type = lib.types.str;
      example = "example.com";
      description = lib.mdDoc "Top-level domain to configure";
    };
    subdomain = lib.mkOption {
      type = lib.types.str;
      example = "calendar";
      description = lib.mdDoc "Subdomain in which to put Radicale";
    };
    enableGit = lib.mkOption {
      type = lib.types.bool;
      description = lib.mdDoc "Whether to automatically commit calendar updates to a Git repo";
    };
    port = lib.mkOption {
      type = lib.types.port;
      description = lib.mdDoc "Radicale port inside container";
      default = 5232;
    };
  };

  config = lib.mkIf cfg.enable {
    # Create radicale user/group on the host with explicit UIDs matching the container.
    # These are historical details: the UID/GID that were auto-allocated before we moved to containers.
    users.users.radicale = {
      uid = 995;
      isSystemUser = true;
      group = "radicale";
      home = filesystem_folder;
    };
    users.groups.radicale.gid = 993;

    # Secrets are decrypted on the host and bind-mounted into the container.
    # They must be readable by the radicale user.
    sops.secrets = {
      "radicale_user" = {
        owner = "radicale";
        group = "radicale";
      };
      "radicale_htcrypt_password" = {
        owner = "radicale";
        group = "radicale";
      };
      "radicale_git_email" = {
        owner = "radicale";
        group = "radicale";
      };
    };

    # Ensure the data directory exists and is owned by radicale
    # d = create if missing, Z = recursively fix ownership (- for mode = don't change)
    systemd.tmpfiles.rules = [
      "d ${filesystem_folder} 0750 radicale radicale -"
      "Z ${filesystem_folder} - radicale radicale -"
    ];

    # The container service must wait for secrets to be available,
    # otherwise bind-mounts of /run/secrets/* will fail.
    # sops-install-secrets is a oneshot that decrypts secrets during activation.
    systemd.services."container@radicale" = {
      after = ["sops-install-secrets.service"];
      requires = ["sops-install-secrets.service"];
    };

    containers.radicale = {
      autoStart = true;
      privateNetwork = true;
      hostAddress = hostAddress;
      localAddress = containerAddress;

      bindMounts = {
        "${filesystem_folder}" = {
          hostPath = filesystem_folder;
          isReadOnly = false;
        };
        "/run/secrets/radicale_htcrypt_password" = {
          hostPath = "/run/secrets/radicale_htcrypt_password";
          isReadOnly = true;
        };
        "/run/secrets/radicale_user" = {
          hostPath = "/run/secrets/radicale_user";
          isReadOnly = true;
        };
        "/run/secrets/radicale_git_email" = {
          hostPath = "/run/secrets/radicale_git_email";
          isReadOnly = true;
        };
      };

      config = {
        config,
        pkgs,
        ...
      }: {
        system.stateVersion = "23.05";

        # The radicale user needs to exist in the container with matching UID/GID
        users.users.radicale = {
          uid = 995;
          isSystemUser = true;
          group = "radicale";
          home = filesystem_folder;
        };
        users.groups.radicale.gid = 993;

        services.radicale = {
          enable = true;
          settings = {
            logging = {
              level = "debug";
            };
            server.hosts = ["0.0.0.0:${toString cfg.port}"];
            auth = {
              type = "htpasswd";
              htpasswd_filename = "/run/secrets/radicale_htcrypt_password";
              htpasswd_encryption = "bcrypt";
            };
            storage =
              if cfg.enableGit
              then {
                filesystem_folder = filesystem_folder;
                hook = "GIT=${pkgs.git}/bin/git GITIGNORE=${./gitignore} /bin/sh ${./githook.sh}";
              }
              else {
                filesystem_folder = filesystem_folder;
              };
          };
        };

        systemd.services.radicale.serviceConfig.ReadWritePaths = [filesystem_folder];

        # Allow inbound traffic on radicale port
        networking.firewall.allowedTCPPorts = [cfg.port];
      };
    };

    # The container service should wait for secrets to be available
    systemd.services."container@radicale" = {
      after = ["sops-nix.service"];
      requires = ["sops-nix.service"];
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
