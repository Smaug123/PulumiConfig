#!/bin/sh

WOODPECKER_AGENT_SECRET=$(cat /run/secrets/woodpecker_agent_secret)
WOODPECKER_GITEA_SECRET=$(cat /run/secrets/gitea_woodpecker_secret)
WOODPECKER_GITEA_CLIENT_OAUTH_ID=$(cat /run/secrets/gitea_woodpecker_oauth_id)

outfile=$(mktemp)
chmod go-rwx "$outfile"
{
echo "WOODPECKER_AGENT_SECRET=$WOODPECKER_AGENT_SECRET"
echo "WOODPECKER_SECRET=$WOODPECKER_AGENT_SECRET"
echo "WOODPECKER_GITEA_SECRET=$WOODPECKER_GITEA_SECRET"
echo "WOODPECKER_GITEA_CLIENT=$WOODPECKER_GITEA_CLIENT_OAUTH_ID"
} >> "$outfile"

mkdir -p /preserve/woodpecker || exit 1
mv "$outfile" /preserve/woodpecker/woodpecker-combined-secrets.txt || exit 2
