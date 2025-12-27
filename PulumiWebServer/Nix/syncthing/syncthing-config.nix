{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.services.syncthing-config;
in {
  options.services.syncthing-config = {
    enable = lib.mkEnableOption "Syncthing file synchronization";
    domain = lib.mkOption {
      type = lib.types.str;
      example = "example.com";
      description = lib.mdDoc "Top-level domain to configure";
    };
    subdomain = lib.mkOption {
      type = lib.types.str;
      example = "syncthing";
      description = lib.mdDoc "Subdomain in which to put Syncthing";
    };
    port = lib.mkOption {
      type = lib.types.port;
      description = lib.mdDoc "Syncthing localhost port";
      default = 8384;
    };
  };

  config = lib.mkIf cfg.enable (let
    filesystem_folder = "/preserve/syncthing/";
  in {
    services.syncthing = {
      enable = true;
      user = "syncthing";
      dataDir = "${filesystem_folder}/data"; # Default folder for new synced folders
      configDir = "${filesystem_folder}/config"; # Folder for Syncthing's settings and keys
      openDefaultPorts = true;
    };

    systemd.services.syncthing.serviceConfig.ReadWritePaths = [filesystem_folder];

    systemd.tmpfiles.rules = ["d ${filesystem_folder} 0750 syncthing syncthing -"];
  });
}
