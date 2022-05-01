{...}: let
  domain = "@@DOMAIN@@";
in {
  security.acme.acceptTerms = true;
  security.acme.defaults.email = "@@ACME_EMAIL@@";
  security.acme.certs = "@@DOMAINS@@";

  networking.firewall.allowedTCPPorts = [
    80 # required for the ACME challenge
    443
  ];

  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    virtualHosts."${domain}" = {
      globalRedirect = "@@WEBROOT_SUBDOMAIN@@.${domain}";
      addSSL = true;
      enableACME = true;
      root = "/preserve/www/html";
    };

    virtualHosts."@@WEBROOT_SUBDOMAIN@@.${domain}" = {
      addSSL = true;
      enableACME = true;
      root = "/preserve/www/html";
      extraConfig = ''
        location ~* \.(?:ico|css|js|gif|jpe?g|png|woff2)$ {
            expires 30d;
            add_header Pragma public;
            add_header Cache-Control "public";
        }
      '';
    };
  };
}
