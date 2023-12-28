#!/bin/sh

touch /tmp/puregym_token
chmod 600 /tmp/puregym_token
$PUREGYM auth --user-email "$(cat /run/secrets/puregym_email)" --pin "$(cat /run/secrets/puregym_pin)" >/tmp/puregym_token
