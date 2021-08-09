#!/bin/bash

# run this from the same directory as the script

set -euo pipefail

RESULTS_DIR=${RESULTS_DIR:-data}
PLOTS_DIR=${PLOTS_DIR:-.}
PLOTPY=./plot-csv.py

if [ ! -d "$RESULTS_DIR" ]; then
    echo "results dir doesn't exist: $RESULTS_DIR"
    exit 1
fi

mkdir -p $PLOTS_DIR

echo "Plotting from $RESULTS_DIR and writing the results to $PLOTS_DIR"

for file in $RESULTS_DIR/*.txt; do
    base=$(basename -s .txt $file)
    echo "Saving plot for $file to $PLOTS_DIR/$base.svg"
    "$PLOTPY" "$file" --sep='\t' --title="Graviton 2 OOOE Buffer Test: $base" \
        --out "$PLOTS_DIR/$base.svg" --nrows=80 --ylabel="Rumtime (ns)" --xlabel="Payload Instruction Count"
done

echo "Complete!"

