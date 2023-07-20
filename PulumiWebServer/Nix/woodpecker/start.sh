#!/bin/sh

export WOODPECKER_AGENT_SECRET
WOODPECKER_AGENT_SECRET=$("$OPENSSL" rand -hex 32)
export WOODPECKER_GITEA_SECRET
WOODPECKER_GITEA_SECRET=$(cat /run/secrets/gitea_woodpecker_secret)
export WOODPECKER_GITEA_CLIENT_OAUTH_ID
WOODPECKER_GITEA_CLIENT_OAUTH_ID=$(cat /run/secrets/gitea_woodpecker_oauth_id)

"$DOCKER" compose -f "/etc/woodpecker.yaml" up
