{lib, ...}: let
  primaryInterface = "eth0";
in {
  # This file was populated at runtime with the networking
  # details gathered from the active system.
  _module.args.primaryInterface = primaryInterface;

  networking = {
    nameservers = [
      "8.8.8.8"
    ];
    defaultGateway = "165.232.32.1";
    defaultGateway6 = "2a03:b0c0:1:d0::1";
    dhcpcd.enable = false;
    usePredictableInterfaceNames = lib.mkForce false;
    interfaces = {
      ${primaryInterface} = {
        ipv4.addresses = [
          {
            address = "165.232.32.114";
            prefixLength = 20;
          }
          {
            address = "10.16.0.6";
            prefixLength = 16;
          }
        ];
        ipv6.addresses = [
          {
            address = "2a03:b0c0:1:d0::12ef:e001";
            prefixLength = 64;
          }
          {
            address = "fe80::38c5:94ff:fe25:fce2";
            prefixLength = 64;
          }
        ];
        ipv4.routes = [
          {
            address = "165.232.32.1";
            prefixLength = 32;
          }
        ];
        ipv6.routes = [
          {
            address = "2a03:b0c0:1:d0::1";
            prefixLength = 128;
          }
        ];
      };
    };
  };
  services.udev.extraRules = ''
    ATTR{address}=="3a:c5:94:25:fc:e2", NAME="${primaryInterface}"
    ATTR{address}=="4e:65:5d:b6:3c:6b", NAME="eth1"
  '';
}
