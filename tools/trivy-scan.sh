#!/bin/bash
set -e

OUTPUT_DIR=$1
mkdir -p $OUTPUT_DIR

echo "[+] Running Trivy image vulnerability scan..."

# Scan any image you want here
trivy image --severity HIGH,CRITICAL \
    -f json -o $OUTPUT_DIR/trivy.json python:3.9

echo "[+] Trivy report saved to $OUTPUT_DIR/trivy.json"
