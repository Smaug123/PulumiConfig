{...}: let
  primaryInterface = "enp2s0";
in {
  # This file was populated at runtime with the networking
  # details gathered from the active system.
  _module.args.primaryInterface = primaryInterface;

  networking = {
    useDHCP = true;
  };
}
