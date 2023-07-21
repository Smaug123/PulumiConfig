{
  pkgs,
  lib,
  config,
  ...
}: {
  options = {
    services.radicale-config = {
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
        description = lib.mdDoc "Radicale localhost port";
        default = 5232;
      };
    };
  };
  config = let
    filesystem_folder = "/preserve/radicale/data";
  in {
    services.radicale = {
      enable = true;
      settings = {
        logging = {
          level = "debug";
        };
        server.hosts = ["0.0.0.0:${toString config.services.radicale-config.port}"];
        auth = {
          type = "htpasswd";
          htpasswd_filename = "/run/secrets/radicale_htcrypt_password";
          htpasswd_encryption = "bcrypt";
        };
        storage =
          if config.services.radicale-config.enableGit
          then {
            filesystem_folder = filesystem_folder;
            hook = "GIT=${pkgs.git}/bin/git GITIGNORE=${./.gitignore} /bin/sh ${./githook.sh}";
          }
          else {};
      };
    };

    systemd.services.radicale.serviceConfig.ReadWritePaths = [filesystem_folder];

    systemd.tmpfiles.rules = ["d ${filesystem_folder} 0750 radicale radicale -"];

    services.nginx.virtualHosts."${config.services.radicale-config.subdomain}.${config.services.radicale-config.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString config.services.radicale-config.port}/";
      };
    };
  };
}
