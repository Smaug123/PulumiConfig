{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.services.syncthing-container;
  filesystem_folder = "/preserve/syncthing";
  # Container networking
  hostAddress = "192.168.100.1";
  containerAddress = "192.168.100.3";
  # Syncthing ports
  syncPort = 22000;
  discoveryPort = 21027;
in {
  options.services.syncthing-container = {
    enable = lib.mkEnableOption "Syncthing file synchronization (containerised)";
  };

  config = lib.mkIf cfg.enable {
    # Create syncthing user/group on the host with explicit UIDs matching the container.
    # These are historical details: the UID/GID that were auto-allocated before we moved to containers.
    users.users.syncthing = {
      uid = 237;
      isSystemUser = true;
      group = "syncthing";
      home = "${filesystem_folder}/data";
    };
    users.groups.syncthing.gid = 237;

    # Ensure the data directory exists and is owned by syncthing
    # d = create if missing, Z = recursively fix ownership (- for mode = don't change)
    systemd.tmpfiles.rules = [
      "d ${filesystem_folder} 0750 syncthing syncthing -"
      "Z ${filesystem_folder} - syncthing syncthing -"
    ];

    # Port forwarding from host to container for Syncthing protocol
    networking.nat = {
      enable = true;
      internalInterfaces = ["ve-syncthing"];
      externalInterface = "eth0";
      forwardPorts = [
        {
          destination = "${containerAddress}:${toString syncPort}";
          proto = "tcp";
          sourcePort = syncPort;
        }
        {
          destination = "${containerAddress}:${toString discoveryPort}";
          proto = "udp";
          sourcePort = discoveryPort;
        }
      ];
    };

    # Open ports on host firewall
    networking.firewall.allowedTCPPorts = [syncPort];
    networking.firewall.allowedUDPPorts = [discoveryPort];

    containers.syncthing = {
      autoStart = true;
      privateNetwork = true;
      hostAddress = hostAddress;
      localAddress = containerAddress;

      bindMounts = {
        "${filesystem_folder}" = {
          hostPath = filesystem_folder;
          isReadOnly = false;
        };
      };

      config = {
        config,
        pkgs,
        ...
      }: {
        system.stateVersion = "23.05";

        # The syncthing user needs to exist in the container with matching UID/GID
        users.users.syncthing = {
          uid = 237;
          isSystemUser = true;
          group = "syncthing";
          home = "${filesystem_folder}/data";
        };
        users.groups.syncthing.gid = 237;

        services.syncthing = {
          enable = true;
          user = "syncthing";
          dataDir = "${filesystem_folder}/data";
          configDir = "${filesystem_folder}/config";
          guiAddress = "0.0.0.0:8384";
          openDefaultPorts = false; # We handle ports manually
        };

        systemd.services.syncthing.serviceConfig.ReadWritePaths = [filesystem_folder];

        # Allow inbound traffic on syncthing ports
        networking.firewall.allowedTCPPorts = [syncPort 8384];
        networking.firewall.allowedUDPPorts = [discoveryPort];
      };
    };
  };
}
