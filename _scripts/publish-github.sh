#!/bin/bash

set -euo pipefail

# This script publishes the site, given as directory
# to github.

ev () {
    echo "$1=${!1-(unset)}"
}

ev GITHUB_WORKSPACE
ev GITHUB_REPOSITORY
ev PUB_BRANCH
ev PUB_DEST_DIR

repo="https://github.com/${GITHUB_REPOSITORY}.git"
ev repo

site_dir=$(readlink -f "$GITHUB_WORKSPACE/_site")
ev site_dir

echo "Commit summary: $(echo "$PUB_COMMIT_MSG" | head -1)"

cd "${GITHUB_WORKSPACE}/output"
pwd

git config user.name "${GITHUB_ACTOR}"
git config user.email "${GITHUB_ACTOR}@users.noreply.github.com"

git rm -r "./$PUB_DEST_DIR" || echo "deleting $PUB_DEST_DIR failed, maybe it doesn't exist yet"
cp -r "$site_dir/." "./$PUB_DEST_DIR"
git add "./$PUB_DEST_DIR"
git commit -m "Site build for: ${GITHUB_SHA} $PUB_COMMIT_MSG"
git push "$repo" "$PUB_BRANCH:$PUB_BRANCH"
