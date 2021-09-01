#!/bin/bash

# Diff the generated site files in two directories, handy for 
# seeing if some source modifications resulted in any changes
# to the html

set -euo pipefail

trap "echo ERROR: Script failed!" ERR

echo "Using left : ${LEFT=_site.old}"
echo "Using right: ${RIGHT=_site}"

if diff -r -Imodified_time -I'Last rebuild' -I'<updated>'  "$LEFT" "$RIGHT"; then
    echo "No changes!"
else
    echo "LEFT differed from RIGHT"
fi

