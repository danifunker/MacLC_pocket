#!/usr/bin/env bash
# sim_trackC.sh - Track C: run the Verilator sim long enough to see whether the
# Mac LC boot ROM's RAM march-test ($A468xx) terminates and the boot ADVANCES,
# then distill cpu_trace.log + console output into a compact, high-signal report.
#
# Run this on a machine with verilator + SDL2 (+ optionally ghdl). It uses only
# repo-relative paths and is safe to invoke from any working directory.
#
# Usage:
#   scripts/sim_trackC.sh [FRAMES]            # default FRAMES=1500
#   REGEN=1 scripts/sim_trackC.sh [FRAMES]    # regenerate CPU .v from .vhd first
#                                             #   (REQUIRED once after editing any
#                                             #    rtl/tg68k/*.vhd; needs ghdl)
#   NOBUILD=1 scripts/sim_trackC.sh           # reuse existing obj_dir/Vemu
#
# Output (all under scratch/trackC/, gitignored):
#   summary.txt      <- the distilled report (ALSO printed to stdout; paste this back)
#   run.stdout / run.stderr
#   trace_head.txt / trace_tail.txt
#   screenshot_frame_*.png
# Full trace stays at verilator/cpu_trace.log (can be large).
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || { echo "cannot cd to repo root"; exit 1; }

FRAMES="${1:-1500}"
VDIR="verilator"
KERNEL_VHD="rtl/tg68k/TG68KdotC_Kernel.vhd"
KERNEL_V="rtl/tg68k/TG68KdotC_Kernel.v"
OUT="scratch/trackC"
LOG="$VDIR/cpu_trace.log"
AWK="$(command -v gawk || command -v awk)"
mkdir -p "$OUT"

# --- 0. CPU .v regen (opt-in) + staleness warning --------------------------
if [ "${REGEN:-0}" = "1" ]; then
    echo ">>> REGEN=1: regenerating $KERNEL_V from VHDL (ghdl)..."
    bash scripts/regen_tg68k.sh || { echo "!!! regen failed - aborting"; exit 1; }
elif [ "$KERNEL_VHD" -nt "$KERNEL_V" ]; then
    echo "!!! WARNING: $KERNEL_VHD is NEWER than $KERNEL_V."
    echo "!!! The build uses the generated .v. Re-run with: REGEN=1 $0 $FRAMES"
    echo "!!! Continuing with the EXISTING (possibly stale) .v in 3s..."; sleep 3
fi

# --- 1. Build --------------------------------------------------------------
if [ "${NOBUILD:-0}" != "1" ]; then
    echo ">>> Building simulator ($VDIR: make)..."
    ( cd "$VDIR" && make ) || { echo "!!! verilator build failed"; exit 1; }
fi
[ -x "$VDIR/obj_dir/Vemu" ] || { echo "!!! $VDIR/obj_dir/Vemu not found"; exit 2; }

# --- 2. Run headless -------------------------------------------------------
# Screenshot cadence (only frames <= FRAMES fire); always grab the final frame.
SHOTS=""
for f in 100 250 400 700 1000 1300; do
    [ "$f" -le "$FRAMES" ] && SHOTS="${SHOTS:+$SHOTS,}$f"
done
SHOTS="${SHOTS:+$SHOTS,}$FRAMES"

echo ">>> Running headless to frame $FRAMES (screenshots: $SHOTS) ..."
rm -f "$LOG" "$VDIR"/screenshot_frame_*.png
( cd "$VDIR" && ./obj_dir/Vemu --headless --screenshot "$SHOTS" --stop-at-frame "$FRAMES" ) \
    >"$OUT/run.stdout" 2>"$OUT/run.stderr"
RC=$?
echo ">>> sim exit=$RC"
mv -f "$VDIR"/screenshot_frame_*.png "$OUT/" 2>/dev/null

[ -f "$LOG" ] || { echo "!!! no cpu_trace.log produced - sim never started tracing"; \
                   echo "    (check $OUT/run.stderr)"; tail -20 "$OUT/run.stderr"; exit 2; }

# --- 3. Analyze ------------------------------------------------------------
grep -v '^--- frame' "$LOG" | head -500  > "$OUT/trace_head.txt"
grep -v '^--- frame' "$LOG" | tail -80   > "$OUT/trace_tail.txt"
TOTAL=$(grep -vc '^--- frame' "$LOG")
BYTES=$(wc -c < "$LOG" | tr -d ' ')

# Single streaming pass: regions(new-in-last-25%), march @addr min/max+samples,
# low-PC (exception entry) count, hottest PCs, first/last PC. Writes temp files.
"$AWK" -v total="$TOTAL" -v out="$OUT" '
function h(s){ return strtonum("0x" s) }
BEGIN{ q1=int(total*0.5); q3=int(total*0.75); n=0; nsamp=0; lown=0; marchn=0; lowcnt=0 }
/^--- frame/ { next }
{
    n++
    f=$1; gsub(/[^0-9]/,"",f); frame=f+0
    pc=$2; sub(/:$/,"",pc); pref=substr(pc,1,6)
    if(n==1){ firstpc=pc; firstframe=frame }
    lastpc=pc; lastframe=frame
    if(n<=q1) seenfirst[pref]=1
    else if(n>q3 && !(pref in seenlast)) seenlast[pref]=frame
    cnt[pc]++
    if(!(pc in samp)){ d=""; for(i=4;i<NF;i++) d=d $i " "; samp[pc]=d }
    pn=h(pc); if(pn>0 && pn<0x1000){ lowcnt++; if(lown<8){ low[lown]=frame":"pc; lown++ } }
    if(pref=="00A468" || pref=="00A469"){
        a=$NF; sub(/^@/,"",a); an=h(a); marchn++
        if(marchn==1){ amin=an; amax=an } else { if(an<amin)amin=an; if(an>amax)amax=an }
        if(marchn % 15000 == 1 && nsamp<45){ msamp[nsamp]="F" frame" @" a; nsamp++ }
    }
}
END{
    print "TOTAL="n"\nFIRSTPC="firstpc"\nFIRSTFRAME="firstframe"\nLASTPC="lastpc"\nLASTFRAME="lastframe > (out"/.meta")
    nnew=0
    for(p in seenlast) if(!(p in seenfirst)){ print p" (first seen frame "seenlast[p]")" > (out"/.newregions"); nnew++ }
    if(nnew==0) print "(none - boot is looping inside already-seen code regions)" > (out"/.newregions")
    for(p in cnt) print cnt[p]"\t"p"\t"samp[p] > (out"/.hot")
    printf "march trace lines: %d\n", marchn        > (out"/.march")
    if(marchn>0){
        printf "march @addr span: min=%X  max=%X  (range=%X bytes)\n", amin, amax, amax-amin > (out"/.march")
        print "sampled @addr over time (every ~15000th march line):"           > (out"/.march")
        for(i=0;i<nsamp;i++) print "  "msamp[i]                                  > (out"/.march")
    }
    print "exception-entry fetches (PC<0x1000): "lowcnt+0 > (out"/.low")
    for(i=0;i<lown;i++) print "  "low[i]                   > (out"/.low")
}' "$LOG"

. "$OUT/.meta"

# Loop check: unique full PCs in the last 2000 trace lines.
LASTUNIQ=$(grep -v '^--- frame' "$LOG" | tail -2000 | awk '{print $2}' | sort -u | wc -l | tr -d ' ')
TOTREGIONS=$(awk -F'\t' '{print substr($2,1,6)}' "$OUT/.hot" | sort -u | wc -l | tr -d ' ')

# Exception/trap token counts
RTE=$(grep -v '^--- frame' "$LOG" | grep -iwc 'rte' || true)
TRAP=$(grep -v '^--- frame' "$LOG" | grep -iwc 'trap' || true)
RESET=$(grep -v '^--- frame' "$LOG" | grep -iwc 'reset' || true)
STOP=$(grep -v '^--- frame' "$LOG" | grep -iwc 'stop' || true)
BERRH=$(grep -cE ' 00A46240:| 008026A0:' "$LOG" || true)

mk(){ # boot-stage marker
    if grep -q "$1" "$LOG"; then echo "  [x] $2"; else echo "  [ ] $2"; fi
}

# --- 4. Assemble summary ---------------------------------------------------
S="$OUT/summary.txt"
{
echo "======================================================================"
echo " TRACK C - Verilator boot analysis     frames=$FRAMES   sim_exit=$RC"
echo "======================================================================"
echo "[trace] $LOG   bytes=$BYTES   instrs(deduped)=$TOTAL   frames=$FIRSTFRAME..$LASTFRAME"
echo "[pc]    first=$FIRSTPC   last=$LASTPC"
echo
echo "--- Boot-stage checklist --------------------------------------------"
mk "00A02E" "ROM early init   (00A02Exx)"
mk "00A463" "Main startup     (00A463xx)"
mk "00A14C" "Hardware init    (00A14Cxx)"
mk "00A4685E" "RAM march test   (00A4685E)"
mk "00A46AF0" "RAM test routine (00A46AF0)"
echo
echo "--- Advancement: PC regions appearing ONLY in the last 25% ----------"
echo " (new regions => forward progress past where it was earlier)"
sed 's/^/  /' "$OUT/.newregions"
echo " total distinct 6-hex PC regions over whole run: $TOTREGIONS"
echo
echo "--- Loop check (last 2000 instrs) -----------------------------------"
echo " unique PCs in last 2000: $LASTUNIQ   => $([ "$LASTUNIQ" -le 4 ] && echo 'LOOPING' || echo 'ADVANCING')"
echo
echo "--- Top 25 hottest PCs ----------------------------------------------"
sort -rn "$OUT/.hot" | head -25 | awk -F'\t' '{printf "  %8d  %-10s %s\n",$1,$2,$3}'
echo
echo "--- RAM march-test address progression (PC 00A468xx/00A469xx) -------"
cat "$OUT/.march" 2>/dev/null || echo "  (no march-region instructions seen)"
echo
echo "--- Exceptions / traps / vector handlers ----------------------------"
echo " disasm token counts:  rte=$RTE  trap=$TRAP  reset=$RESET  stop=$STOP"
echo " berr/early vector-handler PCs hit (00A46240 / 008026A0): $BERRH"
cat "$OUT/.low" 2>/dev/null
echo
echo "--- Last 60 instructions (where it ended up) ------------------------"
tail -60 "$OUT/trace_tail.txt"
echo
echo "--- Console (stderr) ------------------------------------------------"
echo " stderr lines: $(wc -l < "$OUT/run.stderr" | tr -d ' ')"
echo " error/assert/halt/berr/egret/hc05 matches (last 30):"
grep -iE 'error|assert|halt|berr|egret|hc05|fail|stuck' "$OUT/run.stderr" | tail -30 | sed 's/^/   /' || true
echo " stderr tail (last 15):"
tail -15 "$OUT/run.stderr" | sed 's/^/   /'
echo
echo "--- Overlay escape + Egret SR (sim \$display) ------------------------"
# These prove the GOOD path: in sim (egret_behavioral) the Egret SR transaction
# completes and the ROM overlay escapes (1->0). On FPGA (HC05) the HUD shows it
# never escapes. Confirms/refutes the SR-handshake root cause for the FPGA bug.
OVL=$(grep -h 'memoryOverlayOn changed' "$OUT/run.stdout" "$OUT/run.stderr" 2>/dev/null)
SRW=$(grep -hc 'VIA: SR write' "$OUT/run.stdout" "$OUT/run.stderr" 2>/dev/null | awk '{s+=$1} END{print s+0}')
SRI=$(grep -hc 'shift-in' "$OUT/run.stdout" "$OUT/run.stderr" 2>/dev/null | awk '{s+=$1} END{print s+0}')
if echo "$OVL" | grep -q 'changed: 0'; then
    echo " overlay: ESCAPED in sim (memoryOverlayOn 1->0) <= the path the FPGA fails to reach"
else
    echo " overlay: did NOT escape in sim (no 1->0 transition seen)"
fi
echo "$OVL" | sed 's/^/   /' | head -8
echo " VIA SR writes: $SRW    VIA shift-in events: $SRI"
echo " last 6 SR shift-in events (watch bit_cnt 0..7 per byte):"
grep -h 'shift-in' "$OUT/run.stdout" "$OUT/run.stderr" 2>/dev/null | tail -6 | sed 's/^/   /'
echo
echo "--- Screenshots -----------------------------------------------------"
ls -1 "$OUT"/screenshot_frame_*.png 2>/dev/null | sed 's/^/  /' || echo "  (none)"
echo "======================================================================"
} | tee "$S"

# tidy temp files
rm -f "$OUT"/.meta "$OUT"/.newregions "$OUT"/.hot "$OUT"/.march "$OUT"/.low
echo
echo ">>> Full report: $S    (screenshots + logs alongside it in $OUT/)"
