{
  config,
  pkgs,
  ...
}: let
  port = 3001;
in {
  services.gitea = {
    enable = true;
    appName = "Gitea";
    lfs.enable = true;
    stateDir = "/preserve/gitea";
    database = {
      type = "postgres";
      passwordFile = "/preserve/gitea/gitea-db-pass";
    };
    domain = "@@GITEA_SUBDOMAIN@@.@@DOMAIN@@";
    rootUrl = "https://@@GITEA_SUBDOMAIN@@.@@DOMAIN@@/";
    httpPort = port;
    settings = let
      docutils = pkgs.python37.withPackages (ps:
        with ps; [
          docutils
          pygments
        ]);
    in {
      mailer = {
        ENABLED = true;
        FROM = "gitea@" + "@@DOMAIN@@";
      };
      service = {
        REGISTER_EMAIL_CONFIRM = true;
        DISABLE_REGISTRATION = true;
        COOKIE_SECURE = true;
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

  services.nginx.virtualHosts."@@GITEA_SUBDOMAIN@@.@@DOMAIN@@" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString port}/";
    };
  };

  systemd.services.gitea-supply-password = {
    description = "gitea-supply-password";
    wantedBy = ["gitea.service"];
    path = [pkgs.gitea];
    script = ''
      mkdir -p /preserve/gitea && \
      chown -R gitea /preserve/gitea && \
      ln -f /preserve/keys/gitea-admin-pass /preserve/gitea/gitea-admin-pass && \
      chown gitea /preserve/gitea/gitea-admin-pass && \
      ln -f /preserve/keys/gitea-db-pass /preserve/gitea/gitea-db-pass && \
      chown gitea /preserve/gitea/gitea-db-pass
    '';
    serviceConfig = {
      Restart = "no";
      Type = "oneshot";
      User = "root";
      Group = "root";
    };
  };

  # The Gitea module does not allow adding users declaratively
  systemd.services.gitea-add-user = {
    description = "gitea-add-user";
    after = ["gitea-supply-password.service"];
    wantedBy = ["multi-user.target"];
    path = [pkgs.gitea];
    script = ''      TMPFILE=$(mktemp)
      PASSWORD=$(cat /preserve/gitea/gitea-admin-pass)
      set +e
      ${pkgs.gitea} migrate -c /preserve/gitea/data/custom/conf/app.ini
      ${pkgs.gitea}/bin/gitea admin user create --admin --username @@GITEA_ADMIN_USERNAME@@ --password "$PASSWORD" --email @@GITEA_ADMIN_EMAIL@@ 2>"$TMPFILE" 1>"$TMPFILE"
      EXITCODE=$?
      if [ $EXITCODE -eq 1 ]; then
        if grep 'already exists' "$TMPFILE" 2>/dev/null 1>/dev/null; then
          EXITCODE=0
        fi
      fi
      cat "$TMPFILE"
      rm "$TMPFILE"
      exit $EXITCODE
    '';
    serviceConfig = {
      Restart = "no";
      Type = "oneshot";
      User = "gitea";
      Group = "gitea";
      WorkingDirectory = config.services.gitea.stateDir;
    };
    environment = {GITEA_WORK_DIR = config.services.gitea.stateDir;};
  };
}
