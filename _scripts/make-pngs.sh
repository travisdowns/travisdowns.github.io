#!/bin/bash

# Makes PNGs of various sizes out of the passed SVG file
# Requires svgexport and pngcrush to be installed

set -euo pipefail

sizes=(740 1480 2220 2960)

for input in "$@"; do
    stem="${input%.*}"
    echo "> Processing $input, size: $(du -sh $input)"
    for size in "${sizes[@]}"; do
        out="$stem-${size}w.png"
        svgexport "$input" "$out" "$size:"
        echo ">> Out: $out, size $(du -sh $out)"
    done
done
    

