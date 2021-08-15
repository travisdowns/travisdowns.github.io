#!/bin/bash
#
# check the site content using htmlproofer
#

set -euo pipefail

echo "Checking ${SITE:=_site}"

# we ignore status 429 since we get these fairly frequency from github for our site
# pages since I guess this pounds the site pretty hard and pages is like "woah, slow down buddy"
htmlproofer --assume-extension --http-status-ignore=429 --url-ignore '/.*/notexist.html/' "$@" "$SITE"