{pkgs, ...}: let
  port = 5232;
  enableGit = true;
  storage =
    if enableGit
    then {
      hook = "${pkgs.git}/bin/git add -A && (${pkgs.git}/bin/git diff --cached --quiet || ${pkgs.git}/bin/git commit -m 'Changes by '%(user)s)";
      filesystem_folder = "/preserve/radicale/data";
    }
    else {};
in {
  services.radicale = {
    enable = true;
    settings = {
      server.hosts = ["0.0.0.0:${toString port}"];
      auth = {
        type = "htpasswd";
        htpasswd_filename = "/preserve/keys/radicale-users";
        htpasswd_encryption = "bcrypt";
      };
      storage = storage;
    };
  };

  services.nginx.virtualHosts."@@RADICALE_SUBDOMAIN@@.@@DOMAIN@@" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://localhost:${toString port}/";
    };
  };
}
