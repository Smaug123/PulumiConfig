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
    extraRules = [
      {
        users = ["@@USER@@"];
        commands = [
          {
            command = "ALL";
            options = ["NOPASSWD"];
          }
        ];
      }
    ];
  };

  environment.systemPackages = [
    pkgs.vim
  ];
}
