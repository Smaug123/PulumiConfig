#!/bin/sh

# e.g. `PulumiWebServer/Nix`, the directory holding the Nix flake that you want on the remote machine.
# Appropriate `networking.nix`, `hardware-configuration.nix`, and `ssh-keys.json` files, as output
# by the `pulumi up` command, will end up written to this folder.
NIX_FLAKE="$1"

if [ ! -d "$NIX_FLAKE" ]; then
    echo "Flake directory $NIX_FLAKE does not exist; aborting" 1>&2
    exit 1
fi

DOMAIN="$(jq -r .domain "$1/config.json")"

echo "Domain: $DOMAIN"

# TODO this somehow failed to find the right key
AGE_KEY="$(ssh-keyscan "$DOMAIN" | ssh-to-age | tail -1 2>/dev/null)"

if [ -e "/tmp/networking.nix" ]; then
    mv "/tmp/networking.nix" "$NIX_FLAKE"
fi

if [ -e "/tmp/hardware-configuration.nix" ]; then
    mv "/tmp/hardware-configuration.nix" "$NIX_FLAKE"
fi

if [ -e "/tmp/ssh-keys.json" ]; then
    mv "/tmp/ssh-keys.json" "$NIX_FLAKE"
fi

if [ -n "$AGE_KEY" ]; then
    sed -i -E "s!  - &staging_server.+!  - \&staging_server '$AGE_KEY'!g" .sops.yaml || exit 2
fi

sops updatekeys "$NIX_FLAKE/secrets/staging.json" || exit 3

cd "$NIX_FLAKE" || exit 4

nixos-rebuild switch --keep-going --show-trace --no-reexec --flake .#default --target-host "root@$DOMAIN" --build-host "root@$DOMAIN" || exit
