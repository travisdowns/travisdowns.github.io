#!/bin/bash
#
# Check that all external links are live.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MAX_TRIES=5 "$SCRIPT_DIR/call-htmlproofer.sh" --external-only
