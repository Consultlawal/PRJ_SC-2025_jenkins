#!/bin/bash
set -e

OUTPUT_DIR=$1
mkdir -p $OUTPUT_DIR

echo "[+] Running kube-bench CIS Benchmark scan..."

kube-bench --json > $OUTPUT_DIR/kube-bench.json

echo "[+] kube-bench report saved to $OUTPUT_DIR/kube-bench.json"
