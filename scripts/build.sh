#!/usr/bin/env bash
# Build MacLC.rbf via Quartus. Waits for any in-progress quartus to finish.
set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
if [ -r scripts/local.env ]; then . scripts/local.env; fi
export PATH="$QUARTUS_BIN:$PATH"

LOG="output_files/auto_compile_$(date +%Y%m%d_%H%M%S).log"
mkdir -p output_files
echo "[$(date)] Waiting for any in-progress Quartus to finish..." | tee -a "$LOG"
while tasklist 2>/dev/null | grep -qiE "quartus_(map|fit|asm|sta|sh|pgm)\.exe"; do
    sleep 30
done
touch output_files/.compile_in_progress
echo "[$(date)] Starting compile" | tee -a "$LOG"
# `| tee` would mask Quartus's real exit code via the pipeline. Use PIPESTATUS.
quartus_sh --flow compile MacLC 2>&1 | tee -a "$LOG"
RC=${PIPESTATUS[0]}
rm -f output_files/.compile_in_progress
echo "[$(date)] Compile exit=$RC at $(date)" | tee -a "$LOG"
ls -la output_files/MacLC.{sof,rbf} 2>&1 | tee -a "$LOG"
exit $RC
