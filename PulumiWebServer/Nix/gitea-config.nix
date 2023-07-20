{
  config,
  pkgs,
  lib,
  ...
}: {
  options = {
    services.gitea-config = {
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
        description = lib.mdDoc "Gitea localhost port";
        default = 3001;
      };
    };
  };
  config = {
    users.users."gitea".extraGroups = [config.users.groups.keys.name];
    services.gitea = {
      enable = true;
      appName = "Gitea";
      lfs.enable = true;
      stateDir = "/preserve/gitea/data";
      database = {
        type = "postgres";
        passwordFile = "/run/secrets/gitea_server_password";
      };
      settings = let
        docutils = pkgs.python311.withPackages (ps:
          with ps; [
            docutils
            pygments
          ]);
      in {
        mailer = {
          ENABLED = true;
          FROM = "gitea@" + config.services.gitea-config.domain;
        };
        server = {
          ROOT_URL = "https://${config.services.gitea-config.subdomain}.${config.services.gitea-config.domain}/";
          HTTP_PORT = config.services.gitea-config.port;
          DOMAIN = "${config.services.gitea-config.subdomain}.${config.services.gitea-config.domain}";
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
      };
    };

    services.postgresql = {
      enable = true;
      # TODO: make this use the /preserve mount
      # dataDir = "/preserve/postgresql/data";
      authentication = ''
        local gitea all ident map=gitea-users
      '';
      identMap = ''
        gitea-users gitea gitea
      '';
    };

    services.nginx.virtualHosts."${config.services.gitea-config.subdomain}.${config.services.gitea-config.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString config.services.gitea-config.port}/";
      };
    };

    # The Gitea module does not allow adding users declaratively
    systemd.services.gitea-add-user = {
      description = "gitea-add-user";
      wantedBy = ["multi-user.target"];
      path = [pkgs.gitea];
      script = builtins.readFile ./gitea/add-user.sh;
      serviceConfig = {
        Restart = "no";
        Type = "oneshot";
        User = "gitea";
        Group = "gitea";
        WorkingDirectory = config.services.gitea.stateDir;
        SupplementaryGroups = [config.users.groups.keys.name];
      };
      environment = {
        GITEA_WORK_DIR = config.services.gitea.stateDir;
        GITEA = "${pkgs.gitea}/bin/gitea";
      };
    };
  };
}
