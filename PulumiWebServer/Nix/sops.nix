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
  };
}
