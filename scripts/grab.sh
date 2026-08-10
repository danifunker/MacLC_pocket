#!/usr/bin/env bash
# Trigger a MiSTer screenshot and download the newest one (URL-encodes spaces).
# Usage: bash scripts/grab.sh <outfile.png>
set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
. scripts/local.env
HTTP="http://$MISTER_HOST:$MISTER_HTTP_PORT"
OUT="${1:?usage: grab.sh outfile.png}"
mkdir -p "$(dirname "$OUT")"
curl -s -X POST "$HTTP/api/screenshots" >/dev/null
sleep 2
ENC=$(curl -s "$HTTP/api/screenshots" | python -c "import sys,json,urllib.parse as u;d=json.load(sys.stdin);d.sort(key=lambda x:x['modified']);print(u.quote(d[-1]['path']))")
curl -s -o "$OUT" "$HTTP/api/screenshots/$ENC"
echo "$OUT ($(stat -c %s "$OUT" 2>/dev/null) bytes)  <- $ENC"
