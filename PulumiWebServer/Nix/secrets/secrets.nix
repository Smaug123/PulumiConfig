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
      before = [
        "gitea-db-password.service"
        "miniflux-db-password.service"
        "woodpecker-secret.service"
        "container@gitea.service"
        "container@radicale.service"
        "container@miniflux.service"
        "container@puregym.service"
        "container@robocop.service"
        "container@onatrain.service"
        "container@grafana.service"
        "container@prometheus.service"
        "container@syncthing.service"
        "woodpecker-server.service"
        "woodpecker-agent-docker-agent.service"
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

    systemd.services.gitea-db-password.after = ["json-secrets.service"];
    systemd.services.gitea-db-password.wants = ["json-secrets.service"];
    systemd.services.miniflux-db-password.after = ["json-secrets.service"];
    systemd.services.miniflux-db-password.wants = ["json-secrets.service"];
    systemd.services.woodpecker-secret.after = ["json-secrets.service"];
    systemd.services.woodpecker-secret.wants = ["json-secrets.service"];
    systemd.services."container@gitea".after = ["json-secrets.service"];
    systemd.services."container@gitea".wants = ["json-secrets.service"];
    systemd.services."container@radicale".after = ["json-secrets.service"];
    systemd.services."container@radicale".wants = ["json-secrets.service"];
    systemd.services."container@miniflux".after = ["json-secrets.service"];
    systemd.services."container@miniflux".wants = ["json-secrets.service"];
    systemd.services."container@puregym".after = ["json-secrets.service"];
    systemd.services."container@puregym".wants = ["json-secrets.service"];
    systemd.services."container@robocop".after = ["json-secrets.service"];
    systemd.services."container@robocop".wants = ["json-secrets.service"];
    systemd.services."container@onatrain".after = ["json-secrets.service"];
    systemd.services."container@onatrain".wants = ["json-secrets.service"];
    systemd.services."container@grafana".after = ["json-secrets.service"];
    systemd.services."container@grafana".wants = ["json-secrets.service"];
    systemd.services."container@prometheus".after = ["json-secrets.service"];
    systemd.services."container@prometheus".wants = ["json-secrets.service"];
    systemd.services."container@syncthing".after = ["json-secrets.service"];
    systemd.services."container@syncthing".wants = ["json-secrets.service"];
  };
}
