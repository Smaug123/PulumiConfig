{
  config,
  pkgs,
  lib,
  robocop,
  robocop-dashboard,
  ...
}: let
  cfg = config.services.robocop-container;
  # Container networking
  hostAddress = "192.168.100.1";
  containerAddress = "192.168.100.4";
in {
  options.services.robocop-container = {
    enable = lib.mkEnableOption "Robocop server (containerised)";
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
      description = lib.mdDoc "Robocop port inside container";
      default = 8259;
    };
  };

  config = lib.mkIf cfg.enable {
    # Create robocop user/group on the host with explicit UIDs matching the container.
    users.users.robocop = {
      uid = 988;
      isSystemUser = true;
      group = "robocop";
    };
    users.groups.robocop.gid = 983;

    # NAT for container outbound access (required for GitHub and OpenAI API calls)
    networking.nat = {
      enable = true;
      internalInterfaces = ["ve-robocop"];
      externalInterface = "eth0";
    };

    containers.robocop = {
      autoStart = true;
      privateNetwork = true;
      hostAddress = hostAddress;
      localAddress = containerAddress;

      bindMounts = {
        "/etc/robocop/env" = {
          hostPath = "/etc/robocop/env";
          isReadOnly = true;
        };
        # Bind-mount the robocop package from the host's nix store
        "${robocop}" = {
          hostPath = "${robocop}";
          isReadOnly = true;
        };
      };

      config = {
        config,
        pkgs,
        ...
      }: {
        system.stateVersion = "23.05";

        # The robocop user needs to exist in the container with matching UID/GID
        users.users.robocop = {
          uid = 988;
          isSystemUser = true;
          group = "robocop";
        };
        users.groups.robocop.gid = 983;

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

        # Allow inbound traffic on robocop port.
        # Note: robocop-server binds to 0.0.0.0 (see robocop-server/src/main.rs),
        # so it's reachable from the host via containerAddress.
        networking.firewall.allowedTCPPorts = [cfg.port];
      };
    };

    # nginx on the host proxies to the container
    # Dashboard is served directly from host since it's static files
    services.nginx.virtualHosts."${cfg.subdomain}.${cfg.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/ui/" = {
        alias = "${robocop-dashboard}/";
      };
      locations."= /ui" = {
        return = "301 /ui/";
      };
      locations."/" = {
        proxyPass = "http://${containerAddress}:${toString cfg.port}/";
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
