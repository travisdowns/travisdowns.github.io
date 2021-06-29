#!/bin/bash
#
# check the site content using htmlproofer
#

set -euo pipefail

echo "Checking ${SITE:=_site}"

htmlproofer --assume-extension --url-ignore '/.*/notexist.html/' "$@" "$SITE"