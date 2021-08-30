#!/bin/bash

# This script builds the site in CI.

set -euo pipefail

echo "BUILD_SRC=$BUILD_SRC"
echo "BUILD_DEST=$BUILD_DEST"
echo "BUILD_ENV=${BUILD_ENV=production}"
echo "BUILD_EXTRA_OPTIONS=${BUILD_EXTRA_OPTIONS=}"

dest_abs=$(readlink -f "$BUILD_DEST")

cd "$BUILD_SRC"

bundle install

# shellcheck disable=2086
JEKYLL_ENV=production bundle exec jekyll build \
    --destination "$dest_abs" \
    $BUILD_EXTRA_OPTIONS
