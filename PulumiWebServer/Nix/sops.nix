{
  config,
  sops,
  ...
}: {
  sops.defaultSopsFile = ./secrets/staging.json;
}
