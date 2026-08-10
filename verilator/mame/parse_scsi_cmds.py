#!/usr/bin/env python3
"""Parse scsi_trace.lua output into a per-command table (t, frame, start-byte,
dir, CDB) like docs/mame_trace_71boot/cmds_71.txt, plus a reset/restart audit."""
import re, sys

src = sys.argv[1]
nwr = re.compile(r'N WR t=([\d.]+) F=(\d+) off=\w+ reg=(\d+) data=(\w\w)')
dln = re.compile(r'D (\d+) (RD|WR) t=([\d.]+) F=(\d+)')

cdb = []
cdb_t = cdb_f = cdb_sb = None
dack = 0
tcr_after = None
resets = []
out = []

def flush():
    global cdb, cdb_t, cdb_f, cdb_sb, tcr_after
    if cdb:
        d = {1: 'IN', 0: 'OUT', 3: 'STAT'}.get(tcr_after, '?')
        out.append((cdb_t, cdb_f, cdb_sb, d, ''.join(cdb)))
    cdb, cdb_t, cdb_f, cdb_sb, tcr_after = [], None, None, None, None

with open(src, errors='replace') as f:
    for line in f:
        m = dln.match(line)
        if m:
            dack = int(m.group(1))
            continue
        m = nwr.match(line)
        if not m:
            continue
        t, fr, reg, data = float(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4), 16)
        if reg == 3:
            ph = data & 7
            if ph == 2:           # command phase: previous command done
                flush()
                cdb_t, cdb_f, cdb_sb = t, fr, dack
            elif cdb and tcr_after is None:
                tcr_after = ph    # first phase set after the CDB = direction
        elif reg == 0 and cdb_t is not None and tcr_after is None:
            # ODR writes during command phase = CDB bytes (ICR ACK dance
            # interleaves reg1 writes; reg0 carries the byte)
            cdb.append(f'{data:02X}')
        elif reg == 1 and (data & 0x80):
            resets.append((t, fr, line.strip()))
flush()

for t, fr, sb, d, c in out:
    print(f't={t:.6f} F={fr} sb={sb} dir={d} CDB={c}')
print(f'# {len(out)} commands', file=sys.stderr)
print(f'# ICR bit7 (bus reset) writes: {len(resets)}', file=sys.stderr)
for t, fr, l in resets:
    print(f'#   t={t:.6f} F={fr}  {l}', file=sys.stderr)
