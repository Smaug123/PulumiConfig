{lib, ...}: {
  # This file was populated at runtime with the networking
  # details gathered from the active system.
  networking = {
    nameservers = [];
    defaultGateway = "";
    defaultGateway6 = "";
    dhcpcd.enable = false;
    usePredictableInterfaceNames = lib.mkForce false;
    interfaces = {
      eth0 = {
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
