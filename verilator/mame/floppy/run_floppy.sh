#!/usr/bin/env bash
# run_floppy.sh — run MAME `maclc` headless in WSL with a floppy inserted and the
# floppy_tap.lua bus capture installed.  Ground-truth for the drive-ID work.
#
# Usage:
#   bash run_floppy.sh <disk-image> [seconds] [tap_out]
#   SMOKE=1 bash run_floppy.sh <disk-image> [seconds]   # no tap, just boot test
#
# Env: MAME, ROMPATH, RAMSIZE override the defaults.
set -uo pipefail

MAME="${MAME:-/usr/games/mame}"
ROMPATH="${ROMPATH:-$HOME/maclc_roms}"
RAMSIZE="${RAMSIZE:-2M}"
RUNDIR="${RUNDIR:-$HOME/maclc_run}"
HERE="$(cd "$(dirname "$0")" && pwd)"

DISK="${1:?need a disk image path}"
SECONDS_TO_RUN="${2:-12}"
TAP_OUT="${3:-/tmp/floppy_tap.txt}"

mkdir -p "$RUNDIR"
cd "$RUNDIR"

if [ ! -f "$DISK" ]; then echo "disk not found: $DISK" >&2; exit 2; fi

COMMON=( maclc -rompath "$ROMPATH" -ramsize "$RAMSIZE"
         -nothrottle -video none -sound none
         -seconds_to_run "$SECONDS_TO_RUN"
         -flop1 "$DISK" )

if [ "${SMOKE:-0}" = "1" ]; then
	echo "=== SMOKE boot: $DISK for ${SECONDS_TO_RUN}s ==="
	"$MAME" "${COMMON[@]}" 2>&1 | tail -40
else
	export TAP_OUT
	echo "=== TAP run: $DISK for ${SECONDS_TO_RUN}s -> $TAP_OUT ==="
	"$MAME" "${COMMON[@]}" -autoboot_script "$HERE/floppy_tap.lua" 2>&1 | tail -40
	echo "=== tap lines: $(wc -l < "$TAP_OUT" 2>/dev/null || echo 0) ==="
fi
