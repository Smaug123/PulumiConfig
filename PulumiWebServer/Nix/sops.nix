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
    "radicale_user" = {owner = "radicale";};
    "radicale_htcrypt_password" = {owner = "radicale";};
    "radicale_password" = {owner = "radicale";};
    "radicale_git_email" = {owner = "radicale";};
  };
}
