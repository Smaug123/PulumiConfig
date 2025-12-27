{
  config,
  sops,
  ...
}: {
  sops.defaultSopsFile = ./secrets/staging.json;
  sops.secrets = {
    "gitea_server_password" = {owner = "gitea";};
    "gitea_admin_password" = {owner = "gitea";};
    "gitea_admin_username" = {owner = "gitea";};
    "gitea_admin_email" = {owner = "gitea";};
    "gitea_woodpecker_oauth_id" = {owner = "gitea";};
    "gitea_woodpecker_secret" = {owner = "gitea";};
    "woodpecker_agent_secret" = {owner = "gitea";};
    "radicale_user" = {owner = "radicale";};
    "radicale_htcrypt_password" = {owner = "radicale";};
    "radicale_password" = {owner = "radicale";};
    "radicale_git_email" = {owner = "radicale";};
    "miniflux_admin_password" = {owner = "miniflux";};
    "grafana_admin_password" = {owner = "grafana";};
    "grafana_secret_key" = {owner = "grafana";};
  };
}
