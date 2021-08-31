#!/bin/bash
#
# This poorly named script checks the HTML5 markup.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

args=(
    --report-invalid-tags
    --report-missing-names
    --report-script-embeds
    --report-missing-doctype
    --report-eof-tags
    --report-mismatched-tags
    )

# we check if htmlproofer has added any --report options since
# we created the list above
arg_regexp="$(printf '%s|' "${args[@]}")never_match"

missing_args=$(htmlproofer --help 2>/dev/null | grep -- '--report' | { grep -E -v -- "$arg_regexp"; true; })


if [[ -n $missing_args ]]; then
    echo -e "ERROR: Some --report-xxxxx option(s) are missing:\n$missing_args"
    exit 1
fi

"$SCRIPT_DIR/check-html.sh" --checks-to-ignore 'LinkCheck,ImageCheck,ScriptCheck' --check-html "${args[@]}"
