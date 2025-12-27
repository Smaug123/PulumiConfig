{
  config,
  sops,
  ...
}: {
  sops.defaultSopsFile = ./secrets/staging.json;
  sops.secrets = {
    "gitea_woodpecker_oauth_id" = {owner = "gitea";};
    "gitea_woodpecker_secret" = {owner = "gitea";};
    "woodpecker_agent_secret" = {owner = "gitea";};
  };
}
