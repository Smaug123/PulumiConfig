{
  lib,
  config,
  ...
}: let
  cfg = config.services.apps-config;
in {
  options.services.apps-config = {
    enable = lib.mkEnableOption "Apps static file server";
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

  config = lib.mkIf cfg.enable {
    services.nginx.virtualHosts."${cfg.subdomain}.${cfg.domain}" = {
      forceSSL = true;
      enableACME = true;
      root = ./static;
    };
  };
}
