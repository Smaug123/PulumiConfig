#!/bin/sh

touch "$PUREGYM_TOKEN_PATH"
chmod 600 "$PUREGYM_TOKEN_PATH"
$PUREGYM auth --user-email "$(cat /run/secrets/puregym_email)" --pin "$(cat /run/secrets/puregym_pin)" >"$PUREGYM_TOKEN_PATH"
