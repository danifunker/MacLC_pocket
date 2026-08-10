#!/bin/bash
# check_boot.sh - Verify CPU boot progress from Verilator simulation
#
# Usage:
#   ./check_boot.sh              # Analyze existing cpu_trace.log
#   ./check_boot.sh --run        # Run simulation first (30 frames), then analyze
#   ./check_boot.sh --run 100    # Run simulation for N frames, then analyze
#
# Exit codes:
#   0 - CPU is advancing through ROM (boot progressing)
#   1 - CPU never started or stuck at reset
#   2 - cpu_trace.log not found (run with --run or run simulator first)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$SCRIPT_DIR/cpu_trace.log"
FRAMES=30

# Parse args
if [ "$1" = "--run" ]; then
    FRAMES="${2:-30}"
    echo "Running simulation for $FRAMES frames..."
    cd "$SCRIPT_DIR"
    if [ ! -f obj_dir/Vemu ]; then
        echo "ERROR: obj_dir/Vemu not found. Run 'make' first."
        exit 2
    fi
    ./obj_dir/Vemu --stop-at-frame "$FRAMES" >/dev/null 2>/dev/null
fi

if [ ! -f "$LOG" ]; then
    echo "ERROR: $LOG not found. Run with --run or run the simulator first."
    exit 2
fi

# Filter out frame separator lines for analysis
TRACE_LINES=$(grep -v '^--- frame' "$LOG")
TOTAL_LINES=$(echo "$TRACE_LINES" | wc -l | tr -d ' ')
FIRST_PC=$(echo "$TRACE_LINES" | head -1 | awk '{print $2}' | sed 's/://')
LAST_PC=$(echo "$TRACE_LINES" | tail -1 | awk '{print $2}' | sed 's/://')

# Check if CPU ever left reset vector area
# Note: Egret holds 68020 in reset for ~1M HC05 cycles, so short runs (<20 frames) produce no CPU trace
if [ "$TOTAL_LINES" -lt 100 ]; then
    echo "FAIL: Only $TOTAL_LINES instructions executed - CPU may not have started"
    echo "(Egret holds CPU in reset until ~frame 15. Use --run 30 or more.)"
    exit 1
fi

# Get high-level PC range transitions (unique 4-char prefix changes)
MILESTONES=$(echo "$TRACE_LINES" | awk '{pc=substr($2,1,6); if(pc!=last) {print NR" "pc; last=pc}}')
MILESTONE_COUNT=$(echo "$MILESTONES" | wc -l | tr -d ' ')

# Check for known boot stages
HAS_ROM_INIT=$(echo "$MILESTONES" | grep -c "00A02E" || true)
HAS_MAIN_STARTUP=$(echo "$MILESTONES" | grep -c "00A463" || true)
HAS_HW_INIT=$(echo "$MILESTONES" | grep -c "00A14C" || true)
HAS_RAM_TEST=$(echo "$TRACE_LINES" | grep -c "00A46AF0" || true)
HAS_MEM_CLEAR=$(echo "$TRACE_LINES" | grep -c "00A4685E" || true)

# Check last 1000 lines for stuck loop (same PC repeated)
LAST_UNIQUE=$(echo "$TRACE_LINES" | tail -1000 | awk '{print substr($2,1,8)}' | sort -u | wc -l | tr -d ' ')

echo "=== CPU Boot Progress ==="
echo "Total instructions: $TOTAL_LINES"
echo "First PC: $FIRST_PC"
echo "Last PC:  $LAST_PC"
echo "PC range transitions: $MILESTONE_COUNT"
echo ""
echo "Boot stages:"
[ "$HAS_ROM_INIT" -gt 0 ]    && echo "  [x] ROM early init (A02Exx)"    || echo "  [ ] ROM early init (A02Exx)"
[ "$HAS_MAIN_STARTUP" -gt 0 ] && echo "  [x] Main startup (A463xx)"      || echo "  [ ] Main startup (A463xx)"
[ "$HAS_HW_INIT" -gt 0 ]     && echo "  [x] Hardware init (A14Cxx)"     || echo "  [ ] Hardware init (A14Cxx)"
[ "$HAS_RAM_TEST" -gt 0 ]    && echo "  [x] RAM test (A46AF0)"          || echo "  [ ] RAM test (A46AF0)"
[ "$HAS_MEM_CLEAR" -gt 0 ]   && echo "  [x] Memory clear (A4685E)"     || echo "  [ ] Memory clear (A4685E)"
echo ""

if [ "$LAST_UNIQUE" -le 3 ]; then
    echo "Status: LOOP (last 1000 insns only $LAST_UNIQUE unique PCs)"
else
    echo "Status: ADVANCING ($LAST_UNIQUE unique PCs in last 1000 insns)"
fi

# Determine exit code
# Success = got past reset and reached at least ROM init
if [ "$HAS_ROM_INIT" -gt 0 ]; then
    echo "Result: PASS"
    exit 0
else
    echo "Result: FAIL (never reached ROM init)"
    exit 1
fi
