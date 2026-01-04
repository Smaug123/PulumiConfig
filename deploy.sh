#!/bin/sh

# e.g. `PulumiWebServer/Nix`, the directory holding the Nix flake that you want on the remote machine.
# Appropriate `networking.nix`, `hardware-configuration.nix`, and `ssh-keys.json` files, as output
# by the `pulumi up` command, will end up written to this folder.
NIX_FLAKE="$1"

if [ ! -d "$NIX_FLAKE" ]; then
    echo "Flake directory $NIX_FLAKE does not exist; aborting" 1>&2
    echo "usage: deploy.sh PATH_TO_FLAKE_DIR REMOTE_HOST" 1>&2
    exit 1
fi

REMOTE_MACHINE="$2"

if [ -z "$REMOTE_MACHINE" ]; then
    echo "usage: deploy.sh PATH_TO_FLAKE_DIR REMOTE_HOST" 1>&2
    exit 2
fi

echo "Domain: $REMOTE_MACHINE"

cd "$NIX_FLAKE" || exit 4

nixos-rebuild switch --keep-going --show-trace --no-reexec --flake .#default --target-host "root@$REMOTE_MACHINE" --build-host "root@$REMOTE_MACHINE" || exit
