#!/usr/bin/env bash
# run_mame.sh — run MAME's `maclc` headless as ground truth for the LC core.
# See docs/mame_compare.md for the full compare-with-MAME process.
#
# Usage:
#   verilator/mame/run_mame.sh [extra mame args...]
#
# Examples:
#   # Headless boot + per-frame snapshots to /private/tmp/goodroms/snap/maclc/
#   verilator/mame/run_mame.sh -autoboot_script verilator/mame/snap.lua
#
#   # Memory-access tap (edit the TAP_* env or pass them inline):
#   TAP_LO=0xf40000 TAP_HI=0xf40003 TAP_MODE=w TAP_OUT=/tmp/vram.txt \
#     verilator/mame/run_mame.sh -autoboot_script verilator/mame/tap.lua
#
#   # Full maincpu execution trace to /tmp/maincpu.tr (then grep with 00Axxxxx PCs):
#   verilator/mame/run_mame.sh -debug -debugscript verilator/mame/trace.dbg -seconds_to_run 12
#
# Env overrides:
#   MAME    : mame binary       (default /opt/homebrew/bin/mame)
#   ROMPATH : ROM search path    (default /private/tmp/goodroms)
#   RAMSIZE : -ramsize           (default 2M; focus config — also test 10M)
#
# NOTES / GOTCHAS (why the flags are what they are):
#   * macOS has NO `timeout`; bound runs with MAME's own -seconds_to_run.
#   * Use `-video opengl -nowindow`; `-video none` produces NO snapshot.
#   * The debugger's default CPU is the Egret HC05, NOT the 68020 — target
#     `maincpu` explicitly (the trace.dbg script does: `trace file,maincpu`).
#   * MAME maincpu trace PCs are 8-digit `00Axxxxx` — grep with that prefix.
#   * 68020 address mask is global_mask(0x80ffffff): bits 30-24 are ignored,
#     so e.g. $50F40000 aliases to $00F40000 (same as our 24-bit decode).
set -euo pipefail

MAME="${MAME:-/opt/homebrew/bin/mame}"
ROMPATH="${ROMPATH:-/private/tmp/goodroms}"
RAMSIZE="${RAMSIZE:-2M}"

cd "$(dirname "$0")/../.."   # repo root (mame must run from a writable cwd)

exec "$MAME" maclc \
	-rompath "$ROMPATH" -ramsize "$RAMSIZE" \
	-nothrottle -video opengl -nowindow -sound none \
	"$@"
