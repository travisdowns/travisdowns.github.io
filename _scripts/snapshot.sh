#!/bin/bash

# Take screenshots of very HTML page in the site

set -euo pipefail

cleanup() {
    if [[ -n ${SERVERPID-} ]]; then
        echo "Killing http-server pid $SERVERPID"
        kill "$SERVERPID"
    fi
}

trap cleanup EXIT

rand_delay() {
    delay=$(( (RANDOM % 20) + 1 ))s
    echo "Sleeping for $delay"
    sleep $delay
}

SITE_REL=${1-./_site}
SITE_ABS=$(readlink -f "$SITE_REL")
WORKDIR=$(readlink -f ./_snapshot-workdir)

echo "SITE_ABS=$SITE_ABS"
echo "MAX_TRIES=${MAX_TRIES:=5}"

# workaround for https://github.com/uazo/cromite/issues/1241
if [[ -f /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]]; then
    sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
fi

if [[ ! -d "$SITE_ABS" ]]; then
    echo "site directory does not exist: $SITE_ABS"
    exit 1
fi

mkdir -p "$WORKDIR"
cd "$WORKDIR"

npm init -y
npm install "github:travisdowns/snap-site#6e3b0e677d8c72a3e1b4c350a5eb544736bed60c" http-server

NODEBIN=$(npm root)/.bin

echo "NODEBIN=$NODEBIN"

if [[ ! -d $NODEBIN ]]; then
    echo "NODEBIN dir does not exist (or is not a dir)"
    exit 1
fi

"$NODEBIN/http-server" -p0 "$SITE_ABS" > http.stdout 2> http.stderr &
SERVERPID=$!
echo "Server pid: $SERVERPID"
secs=0
until lsof -P -a -p$SERVERPID -itcp; do
    if [[ $secs -gt 60 ]]; then
        echo "http-server failed to come up after 60s"
        exit 1
    fi
    sleep 1
    secs=$((secs+1))
    echo "Waited ${secs}s so far for server to come up"
done

port=$(lsof -P -a -p$SERVERPID -itcp | grep -o 'TCP \*:[0-9]*' | grep -o '[0-9]*')
echo "http-server seems to be up on port $port"

echo "repo           : ${SNAPSHOT_REPO:=$(git config --get remote.origin.url)}"
echo "dest path:     : ${SNAPSHOT_DEST_PATH:=}"
echo "branch         : ${SNAPSHOT_BRANCH:=screenshots}"
echo "Github user    : ${SNAPSHOT_USER-(unset)}"
echo "Github email   : ${SNAPSHOT_EMAIL-(unset)}"
echo "Commit message : ${SNAPSHOT_COMMIT_MSG:=screenshots}"
echo "Excludes       : ${SNAPSHOT_EXCLUDES-(unset)}"
echo "Viewport width : ${SNAPSHOT_WIDTH:=1200}"
echo "Viewport height: ${SNAPSHOT_HEIGHT:=600}"
echo "Color pref     : ${SNAPSHOT_COLOR_PREF:=light}"
echo "npm version    : $(npm -v)"
echo "npm bin        : $(npm bin)"



# When using GitHub actions, we won't by default have permissions to push to the
# target repo unless we provide auth info, which can be the action-provided
# GITHUB_TOKEN if the action is triggered by the same repo we want to save
# the screenshots to
if [[ -n ${SNAPSHOT_REPO_AUTH-} ]]; then
    echo "repo auth      : (set)";
    # we need to inject the auth after the protocol, so
    # https://example.com/repo becomes https://user:token@example.com/repo
    # and currently we only handle https:// URLs
    FULL_REPO=${SNAPSHOT_REPO/'https://'/"https://${SNAPSHOT_REPO_AUTH}@"}
else
    echo "repo auth      : (unset)";
    FULL_REPO=$SNAPSHOT_REPO
fi

gitcmd="git -C dest-repo"


setup_user() {
    if [[ -n ${SNAPSHOT_USER+x} ]]; then
    $gitcmd config user.name "$SNAPSHOT_USER"
    fi
    if [[ -n ${SNAPSHOT_EMAIL+x} ]]; then
        $gitcmd config user.email "$SNAPSHOT_EMAIL"
    fi
}

tries=0

while true; do
    rm -rf dest-repo
    if ! git clone "$FULL_REPO" dest-repo --depth 1 --branch "$SNAPSHOT_BRANCH"; then
        echo "Clone of $SNAPSHOT_BRANCH failed, trying to create it"
        git clone "$FULL_REPO" dest-repo --depth 1 --no-single-branch
        setup_user
        $gitcmd checkout --orphan "$SNAPSHOT_BRANCH"
        $gitcmd rm -rf . > /dev/null
        $gitcmd commit --allow-empty -m "initial commit for $SNAPSHOT_BRANCH [winner: $SNAPSHOT_WIDTH, $SNAPSHOT_COLOR_PREF]"
        if $gitcmd push --set-upstream origin "$SNAPSHOT_BRANCH"; then
            echo "new branch $SNAPSHOT_BRANCH created on remote"
            $gitcmd branch -vv
            $gitcmd branch -u origin/$SNAPSHOT_BRANCH
            $gitcmd branch -vv
            break
        else
            tries=$((tries + 1))
            if [[ $tries -ge $MAX_TRIES ]]; then
                echo "FAILED: new branch creation failed $tries times in a row"
                exit 1
            else
                echo "New branch creation failed (race?) $tries times, retrying..."
                rand_delay
            fi
        fi
    else
        echo "Clone succeeded"
        setup_user
        break
    fi
done

outdir="dest-repo/$SNAPSHOT_DEST_PATH"

if [[ "${SKIP_SNAP:-0}" -eq 0 ]]; then
    [[ $SNAPSHOT_COLOR_PREF == dark ]] && darkarg=--dark
    "$NODEBIN/snap-site" --site-dir="$SITE_ABS" --out-dir="$outdir" \
        --width="$SNAPSHOT_WIDTH" --height="$SNAPSHOT_HEIGHT" \
        --host-port="localhost:$port" ${darkarg-} ${SNAPSHOT_EXCLUDES+"--exclude=$SNAPSHOT_EXCLUDES"}
fi

tries=0
while true; do

    $gitcmd add "./$SNAPSHOT_DEST_PATH"

    # determine the number of files modified and added
    total_count=$($gitcmd diff --name-only --cached                 | wc -l)
    mod_count=$($gitcmd diff --name-only --cached --diff-filter=M | wc -l)
    new_count=$($gitcmd diff --name-only --cached --diff-filter=A | wc -l)

    echo "=========== files ============="
    $gitcmd diff --name-only --cached
    echo "==============================="
    echo "Files to commit: $total_count ($mod_count modified, $new_count new)"

    # we replace various tags in the commit message, if present, with their values
    SNAPSHOT_COMMIT_MSG=${SNAPSHOT_COMMIT_MSG//SNAPSHOT_MOD_TAG/$mod_count}
    SNAPSHOT_COMMIT_MSG=${SNAPSHOT_COMMIT_MSG//SNAPSHOT_NEW_TAG/$new_count}
    SNAPSHOT_COMMIT_MSG=${SNAPSHOT_COMMIT_MSG//SNAPSHOT_WIDTH_TAG/$SNAPSHOT_WIDTH}
    SNAPSHOT_COMMIT_MSG=${SNAPSHOT_COMMIT_MSG//SNAPSHOT_COLOR_PREF_TAG/$SNAPSHOT_COLOR_PREF}


    if [[ $total_count -gt 0 ]]; then
        $gitcmd branch -vv
        echo "Comitting updated screenshots"
        $gitcmd commit -m "$SNAPSHOT_COMMIT_MSG"
        # We do this last-second rebase in case some other publish job has come in and created a new commit
        # which is a common occurence when two commits arrive close together in time: since the repo clone
        # occurs before the screenshot there is a large window for a race to occur where both CI jobs clone
        # commit v1, take their screenshots, one commits v2 and the second fails to push because their head
        # is now stale wrt the remote.
        echo "====== git log before rebase  ======"
        $gitcmd log --oneline --max-count=5
        echo "==================================="
        $gitcmd pull --rebase --strategy-option=theirs origin || echo "Pull failed (expected for new branches)"
        echo "====== git log after rebase  ======"
        $gitcmd log --oneline --max-count=5
        echo "==================================="
        echo "Time before push: $(date +"%T")"
        if $gitcmd push origin "$SNAPSHOT_BRANCH:$SNAPSHOT_BRANCH"; then
            echo "Push succeded"
            break
        else
            echo "Time after  push: $(date +"%T")"
            tries=$((tries + 1))
            if [[ $tries -ge $MAX_TRIES ]]; then
                echo "FAILED: push failed $tries times in a row"
                exit 1
            else
                echo "Push failed (probably a race?) $tries times, retrying..."
                rand_delay
                # we need to undo the commit and do it over again, because things like
                # the number of modified files (and hence the commmit message) may change
                $gitcmd reset --soft origin/$SNAPSHOT_BRANCH
            fi
        fi

    else
        echo "Nothing new to commit..."
        break
    fi
done

echo "snapshot.sh: success"
