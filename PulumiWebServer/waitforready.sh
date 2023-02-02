#!/bin/sh

ADDRESS=$1
PRIVATE_KEY=$2

while ! /usr/bin/ssh "root@$ADDRESS" -o ConnectTimeout=5 -o IdentityFile="$PRIVATE_KEY" -o StrictHostKeyChecking=off echo hello ; do
    echo "Sleeping for 5s"
    sleep 5
done

# For some reason /usr/bin/ssh can get in at this point even though Pulumi cannot :(
# error: ssh: handshake failed: ssh: unable to authenticate, attempted methods [none publickey], no supported methods remain
sleep 10

date
