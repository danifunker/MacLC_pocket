#!/usr/bin/env python3
"""Validate the core's JSON descriptors against the openFPGA spec.

WHY: an over-length or mistyped field does not produce a helpful message on the
Pocket — the whole core descriptor is rejected and you get "Load error in
'core': General error" with a blank About screen, which looks like a bitstream
problem and is not. This caught exactly that: core.json's description was 74
characters against a documented maximum of 63.

Limits are transcribed from https://www.analogue.co/developer/docs
(core-definition-files/*). Where the spec says "integer / hex string" both
forms are accepted.

Usage:  python3 scripts/check_json.py
Exit:   0 = clean, 1 = violations found
"""
import json
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

problems = []
notes = []


def load(name):
    path = os.path.join(ROOT, name)
    if not os.path.exists(path):
        problems.append('%s: MISSING' % name)
        return None
    with open(path, 'rb') as fh:
        raw = fh.read()
    if raw.startswith(b'\xef\xbb\xbf'):
        problems.append('%s: has a UTF-8 BOM' % name)
    try:
        return json.loads(raw.decode('utf-8'))
    except Exception as exc:
        problems.append('%s: invalid JSON — %s' % (name, exc))
        return None


def maxlen(where, field, value, limit):
    if value is None:
        return
    if not isinstance(value, str):
        problems.append('%s.%s must be a string, got %s'
                        % (where, field, type(value).__name__))
        return
    if len(value) > limit:
        problems.append('%s.%s is %d chars, max %d — %r'
                        % (where, field, len(value), limit, value))


# ---------------------------------------------------------------- core.json --
c = load('core.json')
if c:
    core = c.get('core', {})
    if core.get('magic') != 'APF_VER_1':
        problems.append('core.json magic must be "APF_VER_1"')
    m = core.get('metadata', {})
    maxlen('core.metadata', 'shortname', m.get('shortname'), 31)
    maxlen('core.metadata', 'description', m.get('description'), 63)
    maxlen('core.metadata', 'author', m.get('author'), 31)
    maxlen('core.metadata', 'url', m.get('url'), 63)
    maxlen('core.metadata', 'version', m.get('version'), 31)
    maxlen('core.metadata', 'date_release', m.get('date_release'), 10)
    pid = m.get('platform_ids', [])
    if len(pid) > 4:
        problems.append('core.metadata.platform_ids: %d platforms, max 4' % len(pid))
    f = core.get('framework', {})
    if f.get('target_product') != 'Analogue Pocket':
        problems.append('core.framework.target_product must be "Analogue Pocket"')
    if not f.get('dock', {}).get('supported', False):
        problems.append('core.framework.dock.supported must be true')
    cores = core.get('cores', [])
    if len(cores) > 8:
        problems.append('core.cores: %d entries, max 8' % len(cores))
    for i, b in enumerate(cores):
        maxlen('core.cores[%d]' % i, 'name', b.get('name'), 15)
        maxlen('core.cores[%d]' % i, 'filename', b.get('filename'), 15)

# ---------------------------------------------------------------- data.json --
d = load('data.json')
if d:
    slots = d.get('data', {}).get('data_slots', [])
    if len(slots) > 32:
        problems.append('data.json: %d slots, max 32' % len(slots))
    for i, s in enumerate(slots):
        w = 'data.data_slots[%d]' % i
        maxlen(w, 'name', s.get('name'), 15)
        if 'filename' in s:
            maxlen(w, 'filename', s.get('filename'), 31)
        ext = s.get('extensions', [])
        if len(ext) > 4:
            problems.append('%s.extensions: %d, max 4' % (w, len(ext)))
        for e in ext:
            if len(e) > 7:
                problems.append('%s.extensions: %r is %d chars, max 7'
                                % (w, e, len(e)))
        sid = s.get('id')
        try:
            v = int(str(sid), 0)
            if not 0 <= v <= 0xFFFF:
                problems.append('%s.id %s out of 16-bit range' % (w, sid))
        except Exception:
            problems.append('%s.id %r is neither an integer nor a hex string'
                            % (w, sid))

# --------------------------------------------------------------- video.json --
v = load('video.json')
if v:
    modes = v.get('video', {}).get('scaler_modes', [])
    if not modes:
        problems.append('video.json: no scaler_modes defined')
    for i, mo in enumerate(modes):
        for k in ('width', 'height', 'aspect_w', 'aspect_h', 'rotation', 'mirror'):
            if k not in mo:
                problems.append('video.scaler_modes[%d]: missing %s' % (i, k))

# ------------------------------------------------- input / interact / other --
inp = load('input.json')
if inp:
    for ctl in inp.get('input', {}).get('controllers', []):
        for mp in ctl.get('mappings', []):
            key = mp.get('key', '')
            if not key.startswith('pad_'):
                notes.append('input.json: key %r does not look like a pad_* name'
                             % key)

it = load('interact.json')
if it:
    for var in it.get('interact', {}).get('variables', []):
        w = 'interact.variables[%s]' % var.get('name')
        if 'mask' not in var:
            notes.append('%s: no "mask" field (the reference core always sets one)'
                         % w)
        if var.get('type') == 'list':
            for o in var.get('options', []):
                if not isinstance(o.get('value'), str):
                    notes.append('%s: list option value should be a hex STRING'
                                 % w)

load('audio.json')
load('variants.json')

# ------------------------------------------------------------------ report --
for n in notes:
    print('note : %s' % n)
if problems:
    print()
    for p in problems:
        print('FAIL : %s' % p)
    print('\n%d problem(s)' % len(problems))
    sys.exit(1)
print('\njson: all checked limits satisfied')
sys.exit(0)
