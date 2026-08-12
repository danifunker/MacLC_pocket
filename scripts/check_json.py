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
if v:
    modes = v.get('video', {}).get('scaler_modes', [])
    if len(modes) > 8:
        problems.append('video.scaler_modes: %d, max 8' % len(modes))
    for i, mo in enumerate(modes):
        if mo.get('rotation') not in (0, 90, 180, 270):
            problems.append('video.scaler_modes[%d].rotation must be 0/90/180/270,'
                            ' got %r' % (i, mo.get('rotation')))

# --------------------------------------------------------------- input.json --
VALID_KEYS = {
    'pad_btn_a', 'pad_btn_b', 'pad_btn_x', 'pad_btn_y',
    'pad_trig_l', 'pad_trig_r', 'pad_btn_start', 'pad_btn_select',
}
inp = load('input.json')
if inp:
    ctls = inp.get('input', {}).get('controllers', [])
    if len(ctls) > 4:
        problems.append('input.controllers: %d, max 4' % len(ctls))
    for ci, ctl in enumerate(ctls):
        if ctl.get('type') != 'default':
            problems.append('input.controllers[%d].type must be "default"' % ci)
        maps = ctl.get('mappings', [])
        if len(maps) > 8:
            problems.append('input.controllers[%d].mappings: %d, max 8'
                            % (ci, len(maps)))
        for mp in maps:
            maxlen('input.controllers[%d].mappings' % ci, 'name',
                   mp.get('name'), 19)
            key = mp.get('key', '')
            if key not in VALID_KEYS:
                problems.append('input.json: key %r is not a documented keycode'
                                ' (%s)' % (key, ', '.join(sorted(VALID_KEYS))))

# ------------------------------------------------------------ interact.json --
VALID_TYPES = {'radio', 'check', 'slider_u32', 'list', 'number_u32', 'action'}
it = load('interact.json')
if it:
    varsl = it.get('interact', {}).get('variables', [])
    if len(varsl) > 16:
        problems.append('interact.variables: %d entries, max 16 shown'
                        % len(varsl))
    seen = set()
    for var in varsl:
        w = 'interact.variables[%s]' % var.get('name')
        maxlen(w, 'name', var.get('name'), 23)
        if var.get('type') not in VALID_TYPES:
            problems.append('%s.type %r not one of %s'
                            % (w, var.get('type'), sorted(VALID_TYPES)))
        vid = var.get('id')
        try:
            n = int(str(vid), 0)
            if not 0 <= n <= 0xFFFF:
                problems.append('%s.id %s out of 16-bit range' % (w, vid))
            if n in seen:
                problems.append('%s.id %s is duplicated — ids must be unique,'
                                ' persistence is keyed on them' % (w, vid))
            seen.add(n)
        except Exception:
            problems.append('%s.id %r is neither integer nor hex string'
                            % (w, vid))
        for o in var.get('options', []):
            maxlen(w + '.options', 'name', o.get('name'), 23)
        if 'mask' not in var:
            notes.append('%s: no "mask" field (the reference core always sets one)'
                         % w)

load('audio.json')
load('variants.json')

# ------------------------------------------------------- undocumented keys --
#
# WHY THIS EXISTS: the Pocket's parser rejects the WHOLE descriptor on any
# violation and reports only "Load error in 'core': General error" with a blank
# About screen. A key that is not in the spec is as fatal as a mistyped one,
# and it is invisible to every length/type check above.
#
# This caught `"messages": []` in interact.json — present since the initial
# import, carried through six separate "fix the load error" commits because
# each of those was looking for a length or type violation. The spec's
# interact object has exactly two members: magic and variables.
#
# Key sets transcribed from https://www.analogue.co/developer/docs
# (core-definition-files/*). Add to these only with a doc reference.
SCHEMA = {
    'core.json': {
        'core': {'magic', 'metadata', 'framework', 'cores'},
        'core.metadata': {'platform_ids', 'shortname', 'description', 'author',
                          'url', 'version', 'date_release'},
        'core.framework': {'target_product', 'version_required',
                           'sleep_supported', 'chip32_vm', 'dock', 'hardware'},
        'core.framework.dock': {'supported', 'analog_output'},
        'core.framework.hardware': {'link_port', 'cartridge_adapter'},
        'core.cores[]': {'name', 'id', 'filename'},
    },
    'data.json': {
        'data': {'magic', 'data_slots'},
        'data.data_slots[]': {'name', 'id', 'required', 'parameters',
                              'extensions', 'address', 'filename',
                              'size_exact', 'size_maximum', 'nonvolatile',
                              'deferload', 'secondary'},
    },
    'video.json': {
        'video': {'magic', 'scaler_modes'},
        'video.scaler_modes[]': {'width', 'height', 'aspect_w', 'aspect_h',
                                 'rotation', 'mirror'},
    },
    'audio.json': {'audio': {'magic'}},
    'variants.json': {'variants': {'magic', 'variant_list'}},
    'input.json': {
        'input': {'magic', 'controllers'},
        'input.controllers[]': {'type', 'mappings'},
        'input.controllers[].mappings[]': {'id', 'name', 'key'},
    },
    'interact.json': {
        'interact': {'magic', 'variables'},
        'interact.variables[]': {'name', 'id', 'type', 'enabled', 'persist',
                                 'address', 'defaultval', 'value', 'value_off',
                                 'mask', 'options', 'min', 'max', 'step',
                                 'graphical'},
        'interact.variables[].options[]': {'value', 'name'},
    },
}


def check_keys(fname, obj, path):
    allowed = SCHEMA.get(fname, {}).get(path)
    if allowed is not None and isinstance(obj, dict):
        for k in obj:
            if k not in allowed:
                problems.append('%s: %s has undocumented key %r — the Pocket '
                                'rejects the whole descriptor' % (fname, path, k))
    if isinstance(obj, dict):
        for k, val in obj.items():
            if isinstance(val, dict):
                check_keys(fname, val, '%s.%s' % (path, k))
            elif isinstance(val, list):
                for item in val:
                    if isinstance(item, dict):
                        check_keys(fname, item, '%s.%s[]' % (path, k))


for fname in SCHEMA:
    doc = load(fname)
    if doc:
        for root_key, sub in doc.items():
            check_keys(fname, sub, root_key)

# -------------------------------------------------- identity fields agree --
#
# shortname is documented as "Short name used for filesystem", and persisted
# interact values live at /Settings/<author>.<CoreName>/Interact/. Every
# shipping core keeps shortname identical to the core half of its Cores/
# directory (Pocket-Amiga: shortname "Amiga", Cores/Mazamars312.Amiga,
# Settings/Mazamars312.Amiga). Divergence gives the OS two different names for
# one core.
if c:
    m = c.get('core', {}).get('metadata', {})
    author, short = m.get('author', ''), m.get('shortname', '')
    coresdir = os.path.join(ROOT, 'dist', 'Cores')
    dirs = sorted(os.listdir(coresdir)) if os.path.isdir(coresdir) else []
    for dname in dirs:
        # Directories only — a stray .DS_Store or Thumbs.db is not a core.
        if not os.path.isdir(os.path.join(coresdir, dname)):
            continue
        if '.' not in dname:
            continue
        d_author, d_core = dname.split('.', 1)
        if d_author != author:
            problems.append('dist/Cores/%s: directory author %r != '
                            'core.json author %r' % (dname, d_author, author))
        if d_core != short:
            problems.append('dist/Cores/%s: directory core name %r != '
                            'core.json shortname %r — /Settings/%s.%s/ would '
                            'not match the core directory'
                            % (dname, d_core, short, author, short))
    if ' ' in short:
        problems.append('core.metadata.shortname %r contains a space; it is '
                        'used to build filesystem paths' % short)

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
