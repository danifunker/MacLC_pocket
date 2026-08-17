#!/usr/bin/env bash
# build.sh — compile the Pocket core.
#
# Replaces the MiSTer-era script of the same name, which compiled a revision
# called "MacLC" from the repo root and could never have worked here: this
# fork's revision is `ap_core` and its project lives in src/fpga/.
#
# Usage:
#   bash scripts/build.sh            # full compile -> src/fpga/output_files/
#   bash scripts/build.sh --check    # Analysis & Synthesis only (fast syntax check)
#   bash scripts/build.sh --seed 23  # re-roll the fitter seed, then compile
#
# ★ A failing hardware build is often a FIT, not your change — but only once.
#   See docs/BUILD_INSTABILITY.md: one bad fit, re-roll the seed; TWO failures
#   of the same netlist, stop rolling and build a control instead.
set -eu
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

QUARTUS_BIN="${QUARTUS_BIN:-/c/intelFPGA_lite/18.1/quartus/bin64}"
[ -x "$QUARTUS_BIN/quartus_sh.exe" ] || [ -x "$QUARTUS_BIN/quartus_sh" ] || {
    echo "ERROR: quartus_sh not found in $QUARTUS_BIN" >&2
    echo "       set QUARTUS_BIN to your Quartus bin directory" >&2
    exit 1
}
export PATH="$QUARTUS_BIN:$PATH"

CHECK=0
while [ $# -gt 0 ]; do
    case "$1" in
        -c|--check) CHECK=1 ;;
        --seed) shift; SEED="$1"
                sed -i "s/^set_global_assignment -name SEED .*/set_global_assignment -name SEED $SEED/" \
                    src/fpga/ap_core.qsf
                echo "fitter seed -> $SEED" ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

cd src/fpga
mkdir -p output_files
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="output_files/compile_${STAMP}.log"

if [ "$CHECK" = 1 ]; then
    echo "Analysis & Synthesis only (no fit, no bitstream)"
    quartus_map ap_core 2>&1 | tee "$LOG" | grep -iE "^Error|Analysis & Synthesis was" || true
    exit "${PIPESTATUS[0]}"
fi

echo "Full compile — expect ~45 min. Log: src/fpga/$LOG"
quartus_sh --flow compile ap_core > "$LOG" 2>&1
RC=$?

echo ""
sed -n '8p;9p' output_files/ap_core.fit.summary 2>/dev/null
grep -A1 "85C Model Setup" output_files/ap_core.sta.summary 2>/dev/null \
    | grep -E "Slack" | head -3
if [ -f output_files/ap_core.rbf ]; then
    echo ""
    echo "OK: output_files/ap_core.rbf ($(stat -c %s output_files/ap_core.rbf) bytes)"
    echo "Next: bash scripts/make_test_slot.sh src/fpga/output_files/ap_core.rbf <label>"
else
    echo "FAILED (exit $RC) — see src/fpga/$LOG"
fi
exit "$RC"
