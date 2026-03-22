{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.json-secrets;

  deployScript =
    pkgs.writers.writePython3Bin "deploy-secrets"
    {libraries = ps: [ps.bcrypt];}
    (builtins.readFile ./deploy-secrets.py);
in {
  options.services.json-secrets = {
    enable = lib.mkEnableOption "JSON-based secrets management";

    encryptedSecretsFile = lib.mkOption {
      type = lib.types.path;
      default = /etc/secrets.json.age;
      description = "Path to the age-encrypted secrets JSON file";
    };

    ageKeyFile = lib.mkOption {
      type = lib.types.path;
      default = /etc/age-key.txt;
      description = "Path to the age private key for decryption";
    };

    secretsDir = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets";
      description = "Directory where decrypted secrets are placed";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.json-secrets = {
      description = "Decrypt secrets from JSON";
      wantedBy = ["multi-user.target"];
      before =
        lib.optionals config.services.gitea-container.enable [
          "gitea-db-password.service"
          "container@gitea.service"
        ]
        ++ lib.optionals config.services.miniflux-container.enable [
          "miniflux-db-password.service"
          "container@miniflux.service"
        ]
        ++ lib.optionals config.services.woodpecker-config.enable [
          "woodpecker-secret.service"
          "woodpecker-server.service"
          "woodpecker-agent-docker-agent.service"
        ]
        ++ lib.optionals config.services.radicale-container.enable [
          "container@radicale.service"
        ]
        ++ lib.optionals config.services.puregym-container.enable [
          "container@puregym.service"
        ]
        ++ lib.optionals config.services.robocop-container.enable [
          "container@robocop.service"
        ]
        ++ lib.optionals config.services.onatrain-container.enable [
          "container@onatrain.service"
        ]
        ++ lib.optionals config.services.grafana-container.enable [
          "container@grafana.service"
        ]
        ++ lib.optionals config.services.prometheus-container.enable [
          "container@prometheus.service"
        ]
        ++ lib.optionals config.services.syncthing-container.enable [
          "container@syncthing.service"
        ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.concatStringsSep " " [
          "${deployScript}/bin/deploy-secrets"
          (toString cfg.encryptedSecretsFile)
          "--age-binary"
          "${pkgs.age}/bin/age"
          "--key-file"
          (toString cfg.ageKeyFile)
          "--secrets-dir"
          cfg.secretsDir
        ];
      };
    };

    systemd.services.gitea-db-password = lib.mkIf config.services.gitea-container.enable {
      after = ["json-secrets.service"];
      wants = ["json-secrets.service"];
    };
    systemd.services.miniflux-db-password = lib.mkIf config.services.miniflux-container.enable {
      after = ["json-secrets.service"];
      wants = ["json-secrets.service"];
    };
    systemd.services.woodpecker-secret = lib.mkIf config.services.woodpecker-config.enable {
      after = ["json-secrets.service"];
      wants = ["json-secrets.service"];
    };
    systemd.services."container@gitea" = lib.mkIf config.services.gitea-container.enable {
      after = ["json-secrets.service"];
      wants = ["json-secrets.service"];
    };
    systemd.services."container@radicale" = lib.mkIf config.services.radicale-container.enable {
      after = ["json-secrets.service"];
      wants = ["json-secrets.service"];
    };
    systemd.services."container@miniflux" = lib.mkIf config.services.miniflux-container.enable {
      after = ["json-secrets.service"];
      wants = ["json-secrets.service"];
    };
    systemd.services."container@puregym" = lib.mkIf config.services.puregym-container.enable {
      after = ["json-secrets.service"];
      wants = ["json-secrets.service"];
    };
    systemd.services."container@robocop" = lib.mkIf config.services.robocop-container.enable {
      after = ["json-secrets.service"];
      wants = ["json-secrets.service"];
    };
    systemd.services."container@onatrain" = lib.mkIf config.services.onatrain-container.enable {
      after = ["json-secrets.service"];
      wants = ["json-secrets.service"];
    };
    systemd.services."container@grafana" = lib.mkIf config.services.grafana-container.enable {
      after = ["json-secrets.service"];
      wants = ["json-secrets.service"];
    };
    systemd.services."container@prometheus" = lib.mkIf config.services.prometheus-container.enable {
      after = ["json-secrets.service"];
      wants = ["json-secrets.service"];
    };
    systemd.services."container@syncthing" = lib.mkIf config.services.syncthing-container.enable {
      after = ["json-secrets.service"];
      wants = ["json-secrets.service"];
    };
  };
}
