#!/usr/bin/env bash
# =============================================================================
# scan.sh — Host-side wrapper: run scan inside VM and fetch reports
#
# Usage:
#   ./scan.sh              # run full scan + fetch reports
#   ./scan.sh --fetch      # fetch existing reports only (no new scan)
#   ./scan.sh --show-score # print score from latest local report
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPORTS_LOCAL="./reports"
FETCH_ONLY=false
SHOW_SCORE=false

for arg in "$@"; do
    case "$arg" in
        --fetch)       FETCH_ONLY=true  ;;
        --show-score)  SHOW_SCORE=true  ;;
    esac
done

mkdir -p "$REPORTS_LOCAL"

# ── Check VM is running ───────────────────────────────────────────────────
if ! vagrant status 2>/dev/null | grep -q "running"; then
    echo "ERROR: Vagrant VM is not running. Start it with: vagrant up" >&2
    exit 1
fi

# ── Optional: show score from already-fetched report ──────────────────────
if $SHOW_SCORE; then
    LATEST_XML=$(ls -t "$REPORTS_LOCAL"/scan-*-results-*.xml 2>/dev/null | head -1 || true)
    if [[ -z "$LATEST_XML" ]]; then
        echo "No local report XML found. Run ./scan.sh first."
        exit 1
    fi
    echo "Parsing: $LATEST_XML"
    python3 - "$LATEST_XML" << 'PYEOF'
import sys, xml.etree.ElementTree as ET
tree = ET.parse(sys.argv[1])
root = tree.getroot()
counts = {}
for elem in root.iter():
    if elem.tag.split("}")[-1] == "rule-result":
        for child in elem:
            if child.tag.split("}")[-1] == "result":
                val = (child.text or "").strip().lower()
                counts[val] = counts.get(val, 0) + 1
checked = counts.get("pass",0) + counts.get("fail",0)
score   = (counts.get("pass",0) / checked * 100) if checked > 0 else 0.0
print(f"\nCompliance score : {score:.1f}%")
print(f"  PASS           : {counts.get('pass',0)}")
print(f"  FAIL           : {counts.get('fail',0)}")
print(f"  NOT APPLICABLE : {counts.get('notapplicable',0)}")
PYEOF
    exit 0
fi

# ── Run scan inside VM ────────────────────────────────────────────────────
if ! $FETCH_ONLY; then
    echo "=== Running compliance scan inside VM ==="
    vagrant ssh -c "sudo bash /vagrant/provisioning/run-scan.sh"
fi

# ── Fetch reports to host ─────────────────────────────────────────────────
echo ""
echo "=== Fetching reports from VM ==="

# Write SSH config to a temp file for scp
TMP_SSH_CONFIG=$(mktemp)
trap 'rm -f $TMP_SSH_CONFIG' EXIT
vagrant ssh-config > "$TMP_SSH_CONFIG"

# Copy all files from /reports/ on the VM to ./reports/ on the host
scp -F "$TMP_SSH_CONFIG" -r "default:/reports/*" "$REPORTS_LOCAL/" 2>/dev/null || \
    vagrant ssh -c "sudo tar czf /tmp/reports.tar.gz -C /reports ." && \
    scp -F "$TMP_SSH_CONFIG" "default:/tmp/reports.tar.gz" "$REPORTS_LOCAL/" && \
    tar -xzf "$REPORTS_LOCAL/reports.tar.gz" -C "$REPORTS_LOCAL" && \
    rm -f "$REPORTS_LOCAL/reports.tar.gz"

echo ""
echo "Reports saved to: $REPORTS_LOCAL/"
ls -lh "$REPORTS_LOCAL"/*.html "$REPORTS_LOCAL"/*.xml 2>/dev/null | head -20

# ── Parse and print score ─────────────────────────────────────────────────
LATEST_XML=$(ls -t "$REPORTS_LOCAL"/scan-after-results-*.xml 2>/dev/null | head -1 || true)
if [[ -n "$LATEST_XML" ]]; then
    echo ""
    python3 - "$LATEST_XML" << 'PYEOF'
import sys, xml.etree.ElementTree as ET
tree = ET.parse(sys.argv[1])
root = tree.getroot()
counts = {}
for elem in root.iter():
    if elem.tag.split("}")[-1] == "rule-result":
        for child in elem:
            if child.tag.split("}")[-1] == "result":
                val = (child.text or "").strip().lower()
                counts[val] = counts.get(val, 0) + 1
checked = counts.get("pass",0) + counts.get("fail",0)
score   = (counts.get("pass",0) / checked * 100) if checked > 0 else 0.0
print(f"  Score : {score:.1f}%  ({counts.get('pass',0)} pass / {counts.get('fail',0)} fail / {checked} checked)")
if score >= 95:
    print("  ✔  Target met (≥ 95%)")
else:
    print(f"  ✖  Below target (need ≥ 95%). Review ./reports/scan-latest-report.html")
PYEOF
fi

echo ""
echo "To open the HTML report:"
echo "  xdg-open $REPORTS_LOCAL/scan-latest-report.html"
echo ""
echo "To re-run remediation:"
echo "  ./remediate.sh"
