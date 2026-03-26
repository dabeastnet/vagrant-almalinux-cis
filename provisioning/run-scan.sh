#!/usr/bin/env bash
# =============================================================================
# run-scan.sh — Step 5 provisioner (also called by host-side scan.sh)
#
# Runs the final post-remediation compliance scan and prints the score.
# Reports are saved to /reports/ on the guest.
# =============================================================================
set -uo pipefail

echo "============================================================"
echo " STEP 5: Final Compliance Scan"
echo "============================================================"

REPORTS_DIR="/reports"
mkdir -p "$REPORTS_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# ── Resolve SCAP content and profile ──────────────────────────────────────
SCAP_CONTENT=$(cat /etc/cis-scap-content-path 2>/dev/null || echo "")
if [[ -z "$SCAP_CONTENT" || ! -f "$SCAP_CONTENT" ]]; then
    # Fallback search
    for f in \
        /usr/share/xml/scap/ssg/content/ssg-almalinux9-ds.xml \
        /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml; do
        if [[ -f "$f" ]]; then SCAP_CONTENT="$f"; break; fi
    done
fi

PROFILE=""
for p in \
    xccdf_org.ssgproject.content_profile_cis_server_l2 \
    xccdf_org.ssgproject.content_profile_cis; do
    if oscap info "$SCAP_CONTENT" | grep -q "$p"; then
        PROFILE="$p"
        break
    fi
done

echo "SCAP content : $SCAP_CONTENT"
echo "Profile      : $PROFILE"
echo "Timestamp    : $TIMESTAMP"
echo ""

RESULT_XML="$REPORTS_DIR/scan-after-results-${TIMESTAMP}.xml"
RESULT_HTML="$REPORTS_DIR/scan-after-report-${TIMESTAMP}.html"
RESULT_LOG="$REPORTS_DIR/scan-after-${TIMESTAMP}.log"

# ── Run the scan ──────────────────────────────────────────────────────────
echo "--- Running post-remediation scan ---"
oscap xccdf eval \
    --profile          "$PROFILE" \
    --results          "$RESULT_XML" \
    --report           "$RESULT_HTML" \
    --oval-results \
    "$SCAP_CONTENT" \
    2>&1 | tee "$RESULT_LOG" || true

# Create stable symlinks for latest results
ln -sf "$RESULT_XML"  "$REPORTS_DIR/scan-latest-results.xml"
ln -sf "$RESULT_HTML" "$REPORTS_DIR/scan-latest-report.html"

echo ""
echo "Reports saved:"
echo "  XML  : $RESULT_XML"
echo "  HTML : $RESULT_HTML"

# ── Compute compliance score ───────────────────────────────────────────────
echo ""
python3 - "$RESULT_XML" << 'PYEOF'
import sys, xml.etree.ElementTree as ET

result_file = sys.argv[1]
try:
    tree = ET.parse(result_file)
except Exception as e:
    print(f"Could not parse {result_file}: {e}")
    sys.exit(0)

root = tree.getroot()

counts = {"pass": 0, "fail": 0, "error": 0,
          "notapplicable": 0, "notchecked": 0, "informational": 0, "other": 0}

for elem in root.iter():
    local = elem.tag.split("}")[-1]
    if local == "rule-result":
        for child in elem:
            if child.tag.split("}")[-1] == "result":
                val = (child.text or "").strip().lower()
                counts[val] = counts.get(val, 0) + 1

checked = counts["pass"] + counts["fail"]
score   = (counts["pass"] / checked * 100) if checked > 0 else 0.0

bar_len = 50
filled  = int(score / 100 * bar_len)
bar     = "█" * filled + "░" * (bar_len - filled)

print("")
print("╔══════════════════════════════════════════════════════════════╗")
print("║               CIS LEVEL 2 COMPLIANCE RESULT                 ║")
print("╠══════════════════════════════════════════════════════════════╣")
print(f"║  Score : {score:5.1f}%   [{bar}]  ║")
print("╠══════════════════════════════════════════════════════════════╣")
print(f"║  PASS          : {counts['pass']:5d}                                     ║")
print(f"║  FAIL          : {counts['fail']:5d}                                     ║")
print(f"║  NOT APPLICABLE: {counts['notapplicable']:5d}                                     ║")
print(f"║  NOT CHECKED   : {counts['notchecked']:5d}                                     ║")
print(f"║  ERROR         : {counts['error']:5d}                                     ║")
print("╚══════════════════════════════════════════════════════════════╝")
print("")
if score >= 95:
    print("  ✔  TARGET MET: Score ≥ 95% — CIS Level 2 goal achieved.")
elif score >= 85:
    print("  ⚠  CLOSE: Score ≥ 85%. Review /reports/scan-latest-report.html for remaining failures.")
else:
    print("  ✖  BELOW TARGET: Score < 85%. Review remediation log and re-run remediate.sh.")
print("")
PYEOF

echo "=== Scan complete. Retrieve reports with:  ./scan.sh --fetch ==="
