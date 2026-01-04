#!/bin/sh

TMPFILE=$(mktemp)
PASSWORD=$(cat /run/secrets/gitea_admin_password)
GITEA_ADMIN_USERNAME=$(cat /run/secrets/gitea_admin_username)
GITEA_ADMIN_EMAIL=$(cat /run/secrets/gitea_admin_email)
set +e
while [ ! -e /preserve/gitea/data/custom/conf/app.ini ]; do
  sleep 5
done
$GITEA migrate -c /preserve/gitea/data/custom/conf/app.ini
$GITEA admin user create --admin \
  --username "$GITEA_ADMIN_USERNAME" \
  --password "$PASSWORD" \
  --email "$GITEA_ADMIN_EMAIL" \
  2>"$TMPFILE" 1>"$TMPFILE"
EXITCODE=$?
if [ $EXITCODE -eq 1 ]; then
  if grep 'already exists' "$TMPFILE" 2>/dev/null 1>/dev/null; then
    EXITCODE=0
  fi
fi
cat "$TMPFILE"
rm "$TMPFILE"

# Create Woodpecker OAuth2 application if configured
if [ -n "$WOODPECKER_OAUTH_REDIRECT" ]; then
  OAUTH_ID_FILE="/preserve/gitea/woodpecker-oauth-id"
  OAUTH_SECRET_FILE="/preserve/gitea/woodpecker-oauth-secret"
  GITEA_API="http://localhost:${GITEA_PORT}/api/v1"

  # Wait for Gitea API to be ready
  echo "Waiting for Gitea API..."
  while ! curl -sf "${GITEA_API}/version" >/dev/null 2>&1; do
    sleep 2
  done
  echo "Gitea API ready"

  # Check if OAuth app already exists (by checking if we have stored credentials)
  if [ -f "$OAUTH_ID_FILE" ] && [ -f "$OAUTH_SECRET_FILE" ]; then
    EXISTING_ID=$(cat "$OAUTH_ID_FILE")
    # Verify the app still exists in Gitea
    if curl -sf -u "${GITEA_ADMIN_USERNAME}:${PASSWORD}" \
         "${GITEA_API}/user/applications/oauth2" | jq -e ".[] | select(.client_id == \"${EXISTING_ID}\")" >/dev/null 2>&1; then
      echo "Woodpecker OAuth app already exists with client_id: ${EXISTING_ID}"
    else
      # Stored credentials are stale, remove them so we create a new app
      rm -f "$OAUTH_ID_FILE" "$OAUTH_SECRET_FILE"
    fi
  fi

  # Create the OAuth app if we don't have valid credentials
  if [ ! -f "$OAUTH_ID_FILE" ] || [ ! -f "$OAUTH_SECRET_FILE" ]; then
    echo "Creating Woodpecker OAuth2 application..."
    if RESPONSE=$(curl -sf -X POST \
      -u "${GITEA_ADMIN_USERNAME}:${PASSWORD}" \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"Woodpecker CI\", \"redirect_uris\": [\"${WOODPECKER_OAUTH_REDIRECT}\"], \"confidential_client\": true}" \
      "${GITEA_API}/user/applications/oauth2"); then
      CLIENT_ID=$(echo "$RESPONSE" | jq -r '.client_id')
      CLIENT_SECRET=$(echo "$RESPONSE" | jq -r '.client_secret')

      if [ -n "$CLIENT_ID" ] && [ "$CLIENT_ID" != "null" ] && [ -n "$CLIENT_SECRET" ] && [ "$CLIENT_SECRET" != "null" ]; then
        echo "$CLIENT_ID" > "$OAUTH_ID_FILE"
        chmod 640 "$OAUTH_ID_FILE"
        echo "$CLIENT_SECRET" > "$OAUTH_SECRET_FILE"
        chmod 640 "$OAUTH_SECRET_FILE"
        echo "Woodpecker OAuth app created with client_id: ${CLIENT_ID}"
      else
        echo "Failed to parse OAuth response: $RESPONSE"
        EXITCODE=1
      fi
    else
      echo "Failed to create OAuth app"
      EXITCODE=1
    fi
  fi
fi

exit $EXITCODE
