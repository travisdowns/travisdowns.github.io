#!/bin/bash
#
# Check that all internal links are valid.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/call-htmlproofer.sh" --disable-external
