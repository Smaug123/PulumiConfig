{...}: let
  domain = "@@DOMAIN@@";
in {
  security.acme.acceptTerms = true;
  security.acme.certs = {
    ${domain} = {
      email = "@@ACME_EMAIL@@";
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
  };
}
