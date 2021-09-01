#!/bin/bash
#
# Miscellaneous checks
#
set -euo pipefail

echo "Running miscellaenous checks on ${SRC:=.}, ${SITE:=_site}"

# https://stackoverflow.com/a/7170782
# exts=$(find . -type f -printf "%f\n" | grep -F '.' | awk -F. '!a[$NF]++{print $NF}' | sort)

# echo "Line counts by extension:"
# for ext in $exts; do
#     printf '%10s:' "$ext"
#     printf '%8d\n' "$( ( find ./ -name "*.$ext" -print0 | xargs -0 cat ) | wc -l)"
# done

# this trickery is just to avoid having a literal T-O-D-O in this
# script since it will trigger the check below!
word="TOD"O

{ grep --exclude='*.svg' --exclude-dir='.git' -n -I -i -r $word "$SRC"; gexit=$?; } || true
if [[ $gexit -eq 0 ]]; then
    echo "ERROR: $word found in source, see above (ret: $gexit)"
    exit 1
elif [[ $gexit -gt 1 ]]; then
    echo "ERROR: grep failed (ret: $gexit)"
    exit 1
fi

echo "Miscellaneous checks passed, yay!"
