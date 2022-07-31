{pkgs, ...}: let
  port = 5232;
in {
  services.radicale = {
    enable = true;
    settings = {
      server.hosts = ["0.0.0.0:${toString port}"];
      auth = {
        type = "htpasswd";
        htpasswd_filename = "/var/radicale_users";
        htpasswd_encryption = "bcrypt";
      };
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
