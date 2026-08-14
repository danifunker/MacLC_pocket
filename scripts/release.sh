#!/usr/bin/env bash
# release.sh — build the openFPGA release zip; optionally publish to GitHub.
#
# The zip layout is the SD-card root: Cores/, Platforms/, Assets/ — and the
# names are CASE-SENSITIVE for the Linux-based updaters (pupdate, Pocket Sync)
# even though the Pocket's FAT and the macOS/Windows dev filesystems are not.
# The archive is therefore built from a freshly created STAGING tree and the
# entry names are asserted after writing — a case-folded directory that
# survived on disk (the 2026-08-14 dist/platforms incident: macOS kept a
# pre-existing lowercase name across package.sh's mkdir -p) cannot leak in.
#
# Ships: bitstream + the seven core JSONs + icon, Platforms/maclc.json +
# _images/maclc.bin, and an EMPTY Assets/maclc/common/ for the updater to
# create. NEVER ships ROMs or disk images (Apple copyright — the user
# supplies boot0.rom); a guard aborts if any sneak into staging.
#
# Usage:
#   bash scripts/release.sh              build output/danifunker.MacLC_<ver>.zip
#   bash scripts/release.sh --publish    ...then push HEAD and create the
#                                        GitHub release with the zip attached
#                                        (requires gh, authenticated)
set -eu
cd "$(dirname "$0")/.."

AUTHOR="danifunker"
CORE="MacLC"
PLATFORM="maclc"
DEST="dist/Cores/${AUTHOR}.${CORE}"

# Robust python pick (see package.sh for the Windows Store-stub story)
PY_BIN=""
for cand in python3 python py; do
    p="$(command -v "$cand" 2>/dev/null)" || continue
    [ -n "$p" ] || continue
    "$p" -c 'import sys; sys.exit(0)' >/dev/null 2>&1 || continue
    PY_BIN="$p"; break
done
[ -n "$PY_BIN" ] || { echo "ERROR: no working python on PATH"; exit 1; }

VERSION="$("$PY_BIN" -c "import json;print(json.load(open('core.json'))['core']['metadata']['version'])")"
echo "release version (core.json): $VERSION"

# ---- preflight -------------------------------------------------------------
fail=0
for f in bitstream.rbf_r core.json video.json audio.json data.json input.json interact.json variants.json; do
    [ -f "$DEST/$f" ] || { echo "MISSING: $DEST/$f"; fail=1; }
done
[ -f dist/Platforms/${PLATFORM}.json ] || { echo "MISSING: dist/Platforms/${PLATFORM}.json"; fail=1; }
[ -f dist/Platforms/_images/${PLATFORM}.bin ] || echo "note: no platform image (dist/Platforms/_images/${PLATFORM}.bin) — releasing without art"
[ $fail -eq 0 ] || exit 1
for j in "$DEST"/*.json dist/Platforms/${PLATFORM}.json; do
    "$PY_BIN" -c "import json,sys; json.load(open(sys.argv[1]))" "$j" || { echo "BAD JSON: $j"; exit 1; }
done
sz=$(wc -c < "$DEST/bitstream.rbf_r")
[ "$sz" -gt 1500000 ] && [ "$sz" -lt 2500000 ] || { echo "SUSPICIOUS bitstream size: $sz"; exit 1; }

# ---- staging ---------------------------------------------------------------
STAGE="output/release-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/Cores/${AUTHOR}.${CORE}" "$STAGE/Platforms/_images" "$STAGE/Assets/${PLATFORM}/common"
cp "$DEST"/* "$STAGE/Cores/${AUTHOR}.${CORE}/"
cp dist/Platforms/${PLATFORM}.json "$STAGE/Platforms/"
[ -f dist/Platforms/_images/${PLATFORM}.bin ] && cp dist/Platforms/_images/${PLATFORM}.bin "$STAGE/Platforms/_images/"

# Copyright guard: no ROMs / disk images / PRAM dumps may ship.
bad=$(find "$STAGE" -type f \( -iname "*.rom" -o -iname "*.hda" -o -iname "*.dsk" -o -iname "*.img" \
      -o -iname "*.iso" -o -iname "*.vhd" -o -iname "*.nvr" -o -iname "*.chd" \) | head -5)
[ -z "$bad" ] || { echo "FORBIDDEN CONTENT in staging:"; echo "$bad"; exit 1; }

# ---- zip (python zipfile: exact forward-slash names, empty-dir entry) ------
ZIP="output/${AUTHOR}.${CORE}_${VERSION}.zip"
rm -f "$ZIP"
"$PY_BIN" - "$STAGE" "$ZIP" "$PLATFORM" <<'PY'
import os, sys, zipfile
stage, out, platform = sys.argv[1], sys.argv[2], sys.argv[3]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(stage):
        for fn in sorted(files):
            full = os.path.join(root, fn)
            arc = os.path.relpath(full, stage).replace(os.sep, "/")
            z.write(full, arc)
    z.writestr(f"Assets/{platform}/common/", b"")   # empty dir entry
    names = z.namelist()
# case + layout assertions on the FINISHED archive
ok_roots = ("Cores/", "Platforms/", "Assets/")
bad = [n for n in names if not n.startswith(ok_roots)]
assert not bad, f"entries outside canonical roots: {bad}"
assert any(n.startswith("Platforms/") and n.endswith(".json") for n in names), "no Platforms/*.json"
assert any(n.startswith("Cores/") and n.endswith("bitstream.rbf_r") for n in names), "no bitstream"
lower = [n for n in names if n.startswith(("cores/", "platforms/", "assets/"))]
assert not lower, f"case-folded entries: {lower}"
print(f"{out}: {len(names)} entries, all case-correct")
for n in names: print("   ", n)
PY

echo
echo "zip ready: $ZIP"

# ---- publish ---------------------------------------------------------------
if [ "${1:-}" = "--publish" ]; then
    command -v gh >/dev/null || { echo "ERROR: gh CLI not installed/on PATH"; exit 1; }
    BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    echo "pushing $BRANCH to origin..."
    git push origin "$BRANCH"
    NOTES="output/release-notes-${VERSION}.md"
    if [ ! -f "$NOTES" ]; then
        cat > "$NOTES" <<EOF
Macintosh LC core for the Analogue Pocket — ${VERSION}

Install: unzip onto the SD card root. Supply your own Macintosh LC ROM as
\`Assets/${PLATFORM}/common/boot0.rom\` (512 KB) and a bootable disk image as
\`Assets/${PLATFORM}/common/maclc.hda\` (auto-mounts at launch).

Highlights:
- 68020 Macintosh LC: 2/10 MB RAM, 512x384 up to 256 colours, SCSI hard
  disks (2) + CD-ROM (ISO), floppy (1.44M MFM working; 800K GCR known issue)
- Auto-mounts the default hard disk image at core launch
- Boots in 256 colours out of the box
- Display Modes (CRT Trinitron and friends) supported

Known issues: 800K GCR floppies can crash or hang the system; PRAM settings
do not persist across power cycles yet.
EOF
        echo "wrote $NOTES (edit before re-running to customize)"
    fi
    gh release create "v${VERSION}" "$ZIP" \
        --title "MacLC ${VERSION}" \
        --notes-file "$NOTES" \
        --target "$BRANCH"
    echo "release v${VERSION} published."
fi
