{
  pkgs,
  lib,
  config,
  ...
}: {
  options = {
    services.userconfig = {
      user = lib.mkOption {
        type = lib.types.str;
        description = lib.mdDoc "Primary user to create";
      };
      sshKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = lib.mdDoc "SSH public keys to register as authorised login methods for this user";
      };
    };
  };

  config = {
    users.mutableUsers = false;

    users.users."${config.services.userconfig.user}" = {
      isNormalUser = true;
      home = "/home/${config.services.userconfig.user}";
      extraGroups = ["wheel"];
      openssh.authorizedKeys.keys = config.services.userconfig.sshKeys;
    };

    security.sudo = {
      enable = true;
      extraRules = [
        {
          users = ["${config.services.userconfig.user}"];
          commands = [
            {
              command = "ALL";
              options = ["NOPASSWD"];
            }
          ];
        }
      ];
    };

    nix.extraOptions = ''
      experimental-features = nix-command flakes
    '';

    environment.systemPackages = [
      pkgs.vim
      pkgs.git
      pkgs.home-manager
    ];
  };
}
