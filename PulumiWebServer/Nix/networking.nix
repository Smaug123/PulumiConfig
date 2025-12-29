{lib, ...}: let
  primaryInterface = "eth0";
in {
  # This file was populated at runtime with the networking
  # details gathered from the active system.
  _module.args.primaryInterface = primaryInterface;

  networking = {
    nameservers = [];
    defaultGateway = "";
    defaultGateway6 = "";
    dhcpcd.enable = false;
    usePredictableInterfaceNames = lib.mkForce false;
    interfaces = {
      ${primaryInterface} = {
        ipv4.addresses = [];
        ipv6.addresses = [];
        ipv4.routes = [];
        ipv6.routes = [];
      };
    };
  };
  services.udev.extraRules = ''
  '';
}
