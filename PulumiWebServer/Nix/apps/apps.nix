{
  lib,
  config,
  ...
}: {
  options = {
    services.apps-config = {
      domain = lib.mkOption {
        type = lib.types.str;
        example = "example.com";
        description = lib.mdDoc "Top-level domain to configure";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        example = "apps";
        description = lib.mdDoc "Subdomain in which to put apps";
      };
      port = lib.mkOption {
        type = lib.types.port;
        description = lib.mdDoc "App server localhost port";
        default = 9521;
      };
    };
  };
  config = {
    services.nginx.virtualHosts."${config.services.apps-config.subdomain}.${config.services.apps-config.domain}" = {
      forceSSL = true;
      enableACME = true;
      root = ./static;
    };
  };
}
