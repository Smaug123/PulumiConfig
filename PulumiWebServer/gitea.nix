{ config, pkgs, ...}:
let port = 3001; in
{
  services.gitea = {
    enable = true;
    appName = "Gitea";
    cookieSecure = true;
    lfs.enable = true;
    disableRegistration = true;
    database = {
      type = "postgres";
      passwordFile = "/var/gitea-db-pass"; # Where to find the password
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

  # The Gitea module does not allow adding users declaratively
  systemd.services.gitea-add-user = {
    description = "gitea-add-user";
    wants = [ "gitea.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.gitea ];
    script =
      ''TMPFILE=$(mktemp)
PASSWORD=$(cat /var/gitea-admin-pass)
set +e
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
    environment = { GITEA_WORK_DIR = config.services.gitea.stateDir; };
  };
}
