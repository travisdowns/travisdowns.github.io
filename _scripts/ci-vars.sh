#!/bin/bash

# we use variables indirectly via export-vars
# shellcheck disable=SC2034,SC2223

set -euo pipefail

# Sets up the variables needed by the rest of the CI steps
# including embedding some configuration about what branches
# should do what.


if [[ -z "${GITHUB_ACTIONS-}" ]]; then
    # set up some dummy values
    : ${GITHUB_REPOSITORY=defaultrepo}
    : ${GITHUB_REF_SLUG=x}
    : ${GITHUB_ENV="$(pwd)/gh-env.txt"}
    echo "Running outside of github actions, writing to $GITHUB_ENV"
fi

# export and echo the variables given by name as arguments
export-vars() {
    for v in "$@"; do
        if [[ -n ${!v+x} ]]; then
            echo "$v=${!v}" | tee -a "$GITHUB_ENV"
        else
            echo "$v is not set"
        fi
    done
}

echo "GITHUB_REPOSITORY=$GITHUB_REPOSITORY"
if [[ "$GITHUB_REPOSITORY" == */blog-test ]]; then
    EXTRA_BUILD_ARGS="--config _config.yml,_config-test.yml"
else
    EXTRA_BUILD_ARGS=
fi

# maps from a source branch to a publish branch, i.e., for
# changes made to the blog on the source branch, the rendered
# HTML should be checked in on the destination branch
declare -A publish_mapping=(
    ["master"]="gh-pages"
    ["publish-artifact"]="gh-test"
)

echo "GITHUB_REF_SLUG=$GITHUB_REF_SLUG"
PUBLISH_BRANCH=${publish_mapping[$GITHUB_REF_SLUG]-}

echo "======== Exported Variables ========="
export-vars EXTRA_BUILD_ARGS PUBLISH_BRANCH
echo "====================================="