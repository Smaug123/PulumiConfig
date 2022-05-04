{...}: let
  domain = "@@DOMAIN@@";
in {
    services.gitea = {
        enable = true;
        appName = "Gitea";
        database = {
          type = "postgres";
          passwordFile = "/run/keys/gitea-dbpass";   # Where to find the password
        };
        domain = "gitea.${domain}";
        rootUrl = "https://gitea.${domain}/";
        httpPort = 3001;
        extraConfig = let
          docutils =
            pkgs.python37.withPackages (ps: with ps; [
              docutils
              pygments
          ]);
        in ''
          [mailer]
          ENABLED = true
          FROM = "gitea@${domain}"
          [service]
          REGISTER_EMAIL_CONFIRM = true
          [markup.restructuredtext]
          ENABLED = true
          FILE_EXTENSIONS = .rst
          RENDER_COMMAND = ${docutils}/bin/rst2html.py
          IS_INPUT_FILE = false
        '';
      };

      services.postgresql = {
        enable = true;
        authentication = ''
          local gitea all ident map=gitea-users
        '';
        identMap =
          ''
            gitea-users gitea gitea
          '';
      };
}