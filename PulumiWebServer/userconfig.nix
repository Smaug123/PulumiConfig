{...}: {
  users.mutableUsers = false;
  users.users."@@USER@@" = {
    isNormalUser = true;
    home = "/home/@@USER@@";
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = ["@@AUTHORIZED_KEYS@@"];
  };
}
