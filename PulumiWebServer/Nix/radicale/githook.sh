#!/bin/sh

if [ -z "$GIT" ]; then
    echo "Need to call with Git" 1>&2
    exit 2
fi

if [ ! -d ".git" ]; then
    "$GIT" init || exit 3
    "$GIT" config --local core.includesFile "$GITIGNORE" || exit 4
    GIT_AUTHOR_NAME=$(cat /run/secrets/radicale_user)
    "$GIT" config --local user.name "$GIT_AUTHOR_NAME" || exit 5
    GIT_AUTHOR_EMAIL=$(cat /run/secrets/radicale_git_email)
    "$GIT" config --local user.email "$GIT_AUTHOR_EMAIL" || exit 6
fi
"$GIT" add -A || exit 7
if ! "$GIT" diff --cached --quiet; then
    "$GIT" commit -m "Changes by $RADICALE_USER" || exit 8
fi
