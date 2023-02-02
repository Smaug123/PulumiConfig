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
exit $EXITCODE
