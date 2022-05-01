#!/bin/sh

cd PulumiWebServer || exit 1

exit_code=0

if [ -z "$DIGITAL_OCEAN_TOKEN" ]; then
    echo "Get a Digital Ocean personal access token and pass it in as the env var DIGITAL_OCEAN_TOKEN."
    exit_code=1
else
    pulumi config set digitalocean:token "$DIGITAL_OCEAN_TOKEN" --secret
fi

if [ -z "$DIGITAL_OCEAN_SPACES_KEY" ]; then
    echo "Get a Digital Ocean spaces key and pass it in as the env var DIGITAL_OCEAN_SPACES_KEY."
    exit_code=1
else
    pulumi config set digitalocean:spaces_access_id "$DIGITAL_OCEAN_SPACES_KEY" --secret
fi

if [ -z "$DIGITAL_OCEAN_SPACES_SECRET" ]; then
    echo "Get a Digital Ocean spaces key and pass its secret in as the env var DIGITAL_OCEAN_SPACES_SECRET."
    exit_code=1
else
    pulumi config set digitalocean:spaces_secret_key "$DIGITAL_OCEAN_SPACES_SECRET" --secret
fi

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo "Get a Cloudflare API token with edit-DNS rights, and pass it in as the env var CLOUDFLARE_API_TOKEN."
    exit_code=1
else
    pulumi config set cloudflare:apiToken "$CLOUDFLARE_API_TOKEN" --secret
fi

exit $exit_code
