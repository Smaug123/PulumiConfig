{...}: let
  domain = "@@DOMAIN@@";
in {
  security.acme.acceptTerms = true;
  security.acme.certs = {
    ${domain} = {
      email = "@@ACME_EMAIL@@";
      # Staging
      server = "https://acme-staging-v02.api.letsencrypt.org/directory";
    };
  };

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
      addSSL = true;
      enableACME = true;
      root = "/var/www/html";
    };

    virtualHosts."gitea.${domain}" = {
      addSSL = true;
      enableACME = true;
      locations."/".proxyPass = "http://localhost:3001/";
    };
  };
}
