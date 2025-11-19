#!/bin/bash
set -e

OUTPUT_DIR=$1
mkdir -p $OUTPUT_DIR

echo "[+] Exporting Falco runtime security alerts..."

# Adjust the log path depending on your installation
cp /var/log/falco/falco.log $OUTPUT_DIR/falco.log || echo "Falco log not found."

echo "[+] Falco log exported to $OUTPUT_DIR/falco.log"
