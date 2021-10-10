#!/bin/bash

# we use variables indirectly via export-vars
# shellcheck disable=SC2034,SC2223

set -euo pipefail

if [[ "${BASH_VERSINFO:-0}" -lt 4 ]]; then
    echo "ERROR: this script requires bash 4, but you're using bash ${BASH_VERSINFO:-0}" 1>&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROP_DIR="$SCRIPT_DIR/props"

# Sets up the variables needed by the rest of the CI steps
# including embedding some configuration about what branches
# should do what.


if [[ -z "${GITHUB_ACTIONS-}" ]]; then
    # set up some dummy values
    : ${GITHUB_REPOSITORY=defaultrepo}
    : ${GITHUB_REF_SLUG=x}
    : ${GITHUB_ENV="$(pwd)/gh-env.txt"}
    : ${GITHUB_EVENT_NAME=push}
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

# append the given file of env vars to GITHUB env,
# after stripping out comments
export-file() {
grep -v '^#' "$1" > "$GITHUB_ENV"
}

# load base and branch specific vars if any
export-file "$PROP_DIR/default"
if [[ -f "$PROP_DIR/$GITHUB_REF_SLUG" ]]; then
    export-file "$PROP_DIR/default"
fi

# we need to set --config based on the repository, i.e., the
# test repository needs to additionally include the _config-test.yml
# which sets the baseurl appropriately
# the cleanest way I can find to do this is to conditionally set an
# env var which is used in the publish task below
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
echo "GITHUB_EVENT_NAME=$GITHUB_EVENT_NAME"
if [[ $GITHUB_EVENT_NAME == push ]]; then
    PUBLISH_BRANCH=${publish_mapping[$GITHUB_REF_SLUG]-}
    if [[ -z $PUBLISH_BRANCH ]]; then
        site_branch=${GITHUB_REF_SLUG}-site
        if git ls-remote --exit-code --heads origin $site_branch; then
            echo "No explicit branch mapping, but $site_branch exists"
            PUBLISH_BRANCH=$site_branch
        else
            echo "No explicit branch mapping and $site_branch does not exit: will not publish"
        fi
    fi
fi

echo "======== Exported Variables ========="
export-vars EXTRA_BUILD_ARGS PUBLISH_BRANCH
echo "====================================="

echo "::group::GITHUB_ENV Contents"
echo "======== GITHUB_ENV start ========="
cat "$GITHUB_ENV"
echo "======== GITHUB_ENV end ==========="
