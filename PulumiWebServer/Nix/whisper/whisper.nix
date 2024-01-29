{
  config,
  pkgs,
  lib,
  whisper-packages,
  ...
}: {
  options = {
    services.whisper-config = {
      domain = lib.mkOption {
        type = lib.types.str;
        example = "example.com";
        description = lib.mdDoc "Top-level domain to configure";
      };
      subdomain = lib.mkOption {
        type = lib.types.str;
        example = "whisper";
        description = lib.mdDoc "Subdomain in which to put the Whisper server";
      };
      port = lib.mkOption {
        type = lib.types.port;
        description = lib.mdDoc "Whisper localhost port to be forwarded";
        default = 1739;
      };
    };
  };

  config = {
    users.users."whisper".extraGroups = [config.users.groups.keys.name];
    users.users."whisper".group = "whisper";
    users.groups.whisper = {};
    users.users."whisper".isSystemUser = true;

    systemd.services.whisper-server = {
      description = "whisper-server";
      wantedBy = ["multi-user.target"];
      serviceConfig = let
        python = pkgs.python3.withPackages (p: with p; [flask waitress]);
      in {
        Restart = "always";
        Type = "exec";
        User = "whisper";
        Group = "whisper";
        ExecStart = "${python}/bin/python ${./whisper.py}";
      };
      environment = {
        WHISPER_NORMALIZE = "${whisper-packages.normalize}/bin/normalize.sh";
        WHISPER_CLIENT = "${whisper-packages.default}/bin/whisper-cpp";
        WHISPER_PORT = toString config.services.whisper-config.port;
        INDEX_PAGE_PATH = ./transcribe.html;
        YT_DLP = "${pkgs.yt-dlp}/bin/yt-dlp";
      };
    };

    services.nginx.proxyTimeout = "300s";
    services.nginx.clientMaxBodySize = "50M";
    services.nginx.virtualHosts."${config.services.whisper-config.subdomain}.${config.services.whisper-config.domain}" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString config.services.whisper-config.port}/";
      };
    };
  };
}
