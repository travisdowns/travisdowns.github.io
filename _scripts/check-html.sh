#!/bin/bash
#
# check the site content using htmlproofer
#

set -euo pipefail

htmlproofer --assume-extension --url-ignore '/notexist.html' _site