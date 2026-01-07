{
  config,
  pkgs,
  lib,
  onatrain,
  primaryInterface,
  ...
}: let
  cfg = config.services.onatrain-container;
  # Container networking
  hostAddress = "192.168.100.1";
  containerAddress = "192.168.100.10";
in {
  options.services.onatrain-container = {
    enable = lib.mkEnableOption "Onatrain server (containerised)";
    domain = lib.mkOption {
      type = lib.types.str;
      example = "example.com";
      description = lib.mdDoc "Top-level domain to configure";
    };
    subdomain = lib.mkOption {
      type = lib.types.str;
      example = "onatrain";
      description = lib.mdDoc "Subdomain in which to put the Onatrain server";
    };
    port = lib.mkOption {
      type = lib.types.port;
      description = lib.mdDoc "Onatrain port inside container";
      default = 3000;
    };
  };

  config = lib.mkIf cfg.enable {
    # Create onatrain user/group on the host with explicit UIDs
    users.users.onatrain = {
      uid = 987;
      isSystemUser = true;
      group = "onatrain";
    };
    users.groups.onatrain.gid = 982;

    # NAT for container outbound access
    networking.nat = {
      enable = true;
      internalInterfaces = ["ve-onatrain"];
      externalInterface = primaryInterface;
    };

    containers.onatrain = {
      autoStart = true;
      privateNetwork = true;
      hostAddress = hostAddress;
      localAddress = containerAddress;

      bindMounts = {
        "/run/secrets/onatrain_station_api_key" = {
          hostPath = "/run/secrets/onatrain_station_api_key";
          isReadOnly = true;
        };
        "/run/secrets/onatrain_darwin_api_key" = {
          hostPath = "/run/secrets/onatrain_darwin_api_key";
          isReadOnly = true;
        };
        "/run/secrets/onatrain_darwin_arrivals_api_key" = {
          hostPath = "/run/secrets/onatrain_darwin_arrivals_api_key";
          isReadOnly = true;
        };
        # Bind-mount the onatrain package from the host's nix store
        onatrain-package = {
          hostPath = "${onatrain}";
          mountPoint = "${onatrain}";
          isReadOnly = true;
        };
      };

      config = {
        config,
        pkgs,
        ...
      }: {
        system.stateVersion = "23.05";

        # Network configuration: use the host as the default gateway for outbound traffic
        networking.defaultGateway = hostAddress;

        # The onatrain user needs to exist in the container with matching UID/GID
        users.users.onatrain = {
          uid = 987;
          isSystemUser = true;
          group = "onatrain";
        };
        users.groups.onatrain.gid = 982;

        systemd.services.onatrain-server = {
          description = "onatrain-server";
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Restart = "always";
            Type = "simple";
            User = "onatrain";
            Group = "onatrain";
            ExecStart = "${onatrain}/bin/train-server";
            WorkingDirectory = "/var/lib/onatrain";
            StateDirectory = "onatrain";
            StateDirectoryMode = "0700";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
          };
          environment = {
            LISTEN_ADDR = "0.0.0.0:${toString cfg.port}";
            STATE_DIR = "/var/lib/onatrain";
            STATION_API_KEY_FILE = "/run/secrets/onatrain_station_api_key";
            DARWIN_API_KEY_FILE = "/run/secrets/onatrain_darwin_api_key";
            DARWIN_ARRIVALS_API_KEY_FILE = "/run/secrets/onatrain_darwin_arrivals_api_key";
          };
        };

        # Allow inbound traffic on onatrain port
        networking.firewall.allowedTCPPorts = [cfg.port];
      };
    };

    # nginx on the host proxies to the container
    services.nginx.virtualHosts."${cfg.subdomain}.${cfg.domain}" = {
      forceSSL = true;
      enableACME = true;
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
