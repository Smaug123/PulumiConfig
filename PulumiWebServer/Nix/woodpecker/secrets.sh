#!/bin/sh

# Wait for Gitea to create the OAuth credentials (created by gitea-add-user inside container)
GITEA_OAUTH_ID_FILE="/preserve/gitea/woodpecker-oauth-id"
GITEA_OAUTH_SECRET_FILE="/preserve/gitea/woodpecker-oauth-secret"

echo "Waiting for Gitea OAuth credentials..."
timeout=300
elapsed=0
while [ ! -f "$GITEA_OAUTH_ID_FILE" ] || [ ! -f "$GITEA_OAUTH_SECRET_FILE" ]; do
  sleep 5
  elapsed=$((elapsed + 5))
  if [ $elapsed -ge $timeout ]; then
    echo "Timeout waiting for Gitea OAuth credentials"
    exit 1
  fi
done
echo "Gitea OAuth credentials found"

WOODPECKER_AGENT_SECRET=$(cat /run/secrets/woodpecker_agent_secret)
WOODPECKER_GITEA_SECRET=$(cat "$GITEA_OAUTH_SECRET_FILE")
WOODPECKER_GITEA_CLIENT_OAUTH_ID=$(cat "$GITEA_OAUTH_ID_FILE")

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
