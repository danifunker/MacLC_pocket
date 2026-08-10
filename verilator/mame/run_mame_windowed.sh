#!/usr/bin/env bash
# run_mame_windowed.sh — INTERACTIVE maclc for setting the display depth.
#
# Same machine config / cwd / ROMPATH / nvram+diff location as run_mame.sh, but
# WINDOWED + throttled + mouse, so you can drive the Monitors control panel. The
# depth you pick persists (MAME nvram/maclc/egret + the CHD diff/), so the next
# HEADLESS capture (run_mame.sh ... vram_extent.lua / snap.lua) comes up at that
# depth. See docs/video_oracle_maclc.md.
#
# Usage:
#   verilator/mame/run_mame_windowed.sh                 # boot System 6.0.8 HD
#   (then: Apple menu -> Control Panel -> Monitors -> pick a depth -> close ->
#    quit MAME. The chosen depth is remembered for the headless oracle run.)
set -euo pipefail

MAME="${MAME:-/opt/homebrew/bin/mame}"
ROMPATH="${ROMPATH:-/private/tmp/goodroms}"
RAMSIZE="${RAMSIZE:-2M}"
HD="${HD:-/private/tmp/goodroms/hd608.chd}"

cd "$(dirname "$0")/../.."   # repo root (matches run_mame.sh: same nvram/diff)

exec "$MAME" maclc \
	-rompath "$ROMPATH" -ramsize "$RAMSIZE" -hard "$HD" \
	-window -throttle -video opengl \
	"$@"
