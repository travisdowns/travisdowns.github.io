#!/bin/bash
#
# check the site content using htmlproofer
#

set -euo pipefail

echo "Checking ${SITE:=_site}, MAX_TRIES=${MAX_TRIES:=1}"
echo "Additional arguments: $*"

hpver=$(htmlproofer --version | cut -d' ' -f2)
echo "htmlproofer version is $hpver"
# https://unix.stackexchange.com/a/567537/87246 https://creativecommons.org/licenses/by-sa/4.0/
if ! printf '%s\n%s\n' "$hpver" "4" | sort --check=quiet --version-sort; then
    echo "This script only works with htmlproofer versions less than 4, your version is $hpver"
    exit 1
fi

# we ignore status 429 since we get these fairly frequency from github for our site
# pages since I guess this pounds the site pretty hard and pages is like "woah, slow down buddy"

tries=0

# ignore notes:
# docs.github.com: returns 403 to the htmlproofer even though browsers work fine
# blog.cloudflare.com: returns 403 at least when run in github actions for an unknown reason
# twitter.com: infinite 302 redirect loop, perhaps due to cookies
# reddit, encycolorpedia, linux.die.net: 403 to htmlproofer when run from GHA
ignored_urls="\
/notexist.html/,\
/docs.github.com/,\
/xblog.cloudflare.com/on-the-dangers-of-intels-frequency-scaling/,\
/reddit.com/,\
/encycolorpedia.com/,\
/linux.die.net/,\
/twitter.com/"

echo "$ignored_urls"

# the below can change the user-agent but it seems counter-productive currently
# --typhoeus-config='{"headers":{"User-Agent":"Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"}}' \

while true; do
    htmlproofer \
        --assume-extension \
        --http-status-ignore=429 \
        --url-ignore "$ignored_urls" \
        --internal-domains travisdowns.github.io,0.0.0.0:4000 \
        --hydra-config='{ "max_concurrency": 5 }' "$@" "$SITE" && break
    tries=$((tries + 1))
    if [[ $tries -ge $MAX_TRIES ]]; then
        echo "FAILED: htmlproofer failed $tries times in a row"
        exit 1
    fi
    echo "trying again (tried $tries times)"
done
