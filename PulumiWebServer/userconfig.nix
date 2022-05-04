{pkgs, ...}: {
  users.mutableUsers = false;
  users.users."@@USER@@" = {
    isNormalUser = true;
    home = "/home/@@USER@@";
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = ["@@AUTHORIZED_KEYS@@"];
  };

  security.sudo = {
    enable = true;
  };

  environment.systemPackages = [
    pkgs.vim
  ];
}
