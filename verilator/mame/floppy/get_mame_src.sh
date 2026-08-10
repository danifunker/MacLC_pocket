#!/usr/bin/env bash
set -uo pipefail
cd /tmp
curl -fsSL "https://raw.githubusercontent.com/mamedev/mame/mame0264/src/devices/machine/swim1.cpp" -o /tmp/swim1.cpp && echo "swim1.cpp: $(wc -l < /tmp/swim1.cpp) lines"
curl -fsSL "https://raw.githubusercontent.com/mamedev/mame/mame0264/src/devices/imagedev/floppy.cpp" -o /tmp/floppy.cpp && echo "floppy.cpp: $(wc -l < /tmp/floppy.cpp) lines"
echo "=== floppy.cpp mac_floppy wpt_r ==="
grep -nE "mac_floppy_device::wpt_r|::wpt_r" /tmp/floppy.cpp
