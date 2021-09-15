#!/bin/bash
#
# check the site content using htmlproofer
#

set -euo pipefail

echo "Checking ${SITE:=_site}, MAX_TRIES=${MAX_TRIES:=1}"
echo "Additional arguments: $*"
# we ignore status 429 since we get these fairly frequency from github for our site
# pages since I guess this pounds the site pretty hard and pages is like "woah, slow down buddy"

tries=0

while true; do
    htmlproofer \
        --assume-extension \
        --http-status-ignore=429 \
        --url-ignore '/.*/notexist.html/' \
        --internal-domains travisdowns.github.io,0.0.0.0:4000 \
        --hydra-config='{ "max_concurrency": 5 }' "$@" "$SITE" && break
    tries=$((tries + 1))
    if [[ $tries -ge $MAX_TRIES ]]; then
        echo "FAILED: htmlproofer failed $tries times in a row"
        exit 1
    fi
    echo "trying again (tried $tries times)"
done
