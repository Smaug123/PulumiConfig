{pkgs, ...}: let
  domain = "@@DOMAIN@@";
in let
  subdomain = "@@GITEA_SUBDOMAIN@@";
in {
  services.gitea = {
    enable = true;
    appName = "Gitea";
    cookieSecure = true;
    lfs.enable = true;
    disableRegistration = true;
    database = {
      type = "postgres";
      passwordFile = "/run/keys/gitea-dbpass"; # Where to find the password
    };
    domain = "${subdomain}.${domain}";
    rootUrl = "https://${subdomain}.${domain}/";
    httpPort = 3001;
    settings = let
      docutils = pkgs.python37.withPackages (ps:
        with ps; [
          docutils
          pygments
        ]);
    in {
      mailer = {
        ENABLED = true;
        FROM = "gitea@${domain}";
      };
      service = {
        REGISTER_EMAIL_CONFIRM = true;
      };
      "markup.restructuredtext" = {
        ENABLED = true;
        FILE_EXTENSIONS = ".rst";
        RENDER_COMMAND = "${docutils}/bin/rst2html.py";
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
}
