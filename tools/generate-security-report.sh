#!/bin/bash
set -e

DATE=$(date +"%Y-%m-%d-%H-%M")
OUTPUT_DIR="reports/$DATE"
mkdir -p $OUTPUT_DIR

echo "[+] Running Trivy image scan..."
trivy image --severity HIGH,CRITICAL -f json -o $OUTPUT_DIR/trivy.json python:3.9

echo "[+] Running Kube-bench..."
kube-bench --json > $OUTPUT_DIR/kube-bench.json

echo "[+] Exporting Falco alerts..."
cp /var/log/falco/falco.log $OUTPUT_DIR/falco.log

echo "[+] Generating PDF report..."
pandoc $OUTPUT_DIR/*.json -o $OUTPUT_DIR/security-report.pdf

echo "[+] Report generated at $OUTPUT_DIR/security-report.pdf"






# #!/bin/bash
# set -e

# REPORT_DIR="reports"
# mkdir -p $REPORT_DIR

# REPORT_MD="$REPORT_DIR/security-report.md"
# REPORT_PDF="$REPORT_DIR/security-report.pdf"

# echo "# Container Security Mesh – Scan Report" > $REPORT_MD
# echo "Generated on: $(date)" >> $REPORT_MD
# echo "" >> $REPORT_MD

# echo "## 1. Trivy Image Scan" >> $REPORT_MD
# trivy image --severity HIGH,CRITICAL --format table yourimage:latest >> $REPORT_MD 2>&1 || true
# echo "" >> $REPORT_MD

# echo "## 2. Trivy File System Scan" >> $REPORT_MD
# trivy fs --severity HIGH,CRITICAL --format table . >> $REPORT_MD 2>&1 || true
# echo "" >> $REPORT_MD

# echo "## 3. Kubesec Manifest Scan" >> $REPORT_MD
# kubesec scan k8s-manifests/*.yaml >> $REPORT_MD 2>&1 || true
# echo "" >> $REPORT_MD

# echo "## 4. Kube-Bench Scan" >> $REPORT_MD
# kube-bench run --json >> $REPORT_MD 2>&1 || true
# echo "" >> $REPORT_MD

# echo "## 5. Falco Logs (Runtime detection)" >> $REPORT_MD
# cat /var/log/falco-events.log >> $REPORT_MD 2>&1 || true
# echo "" >> $REPORT_MD

# # Convert Markdown → PDF
# pandoc $REPORT_MD -o $REPORT_PDF

# echo "✔ Security PDF report generated at: $REPORT_PDF"
