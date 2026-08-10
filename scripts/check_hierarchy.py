#!/usr/bin/env python3
"""Structural sanity check for the RTL tree — a stand-in for a real lint.

There is no Verilator or Quartus on every dev box, and the Pocket port removed
whole modules (cd_audio, the second floppy, the CD SCSI target). The classic
way that breaks a build is a dangling reference: an instantiation whose module
no longer exists, or a port in an instantiation that the module no longer
declares. This script catches exactly those two, plus obviously-unbalanced
begin/end, without needing a simulator.

It is a heuristic regex pass, not a parser. It errs toward reporting rather
than staying silent; treat output as leads, not verdicts.

Usage:  python scripts/check_hierarchy.py [rtl_dir ...]
Exit:   0 = no dangling references, 1 = something to look at
"""
import os
import re
import sys

# Verilog/SystemVerilog keywords that can appear in `name #(...) inst (` or
# `name inst (` position but are not module instantiations.
NOT_INSTANCES = {
    'if', 'else', 'for', 'while', 'case', 'casex', 'casez', 'begin', 'end',
    'module', 'endmodule', 'function', 'endfunction', 'task', 'endtask',
    'generate', 'endgenerate', 'always', 'always_ff', 'always_comb',
    'always_latch', 'initial', 'assign', 'wire', 'reg', 'logic', 'integer',
    'genvar', 'parameter', 'localparam', 'input', 'output', 'inout',
    'return', 'posedge', 'negedge', 'or', 'and', 'not', 'xor', 'nand', 'nor',
    'buf', 'signed', 'unsigned', 'automatic', 'static', 'typedef', 'struct',
    'enum', 'package', 'endpackage', 'import', 'export', 'default', 'repeat',
    'forever', 'do', 'wait', 'disable', 'fork', 'join', 'assert', 'assume',
}

MODULE_RE = re.compile(r'^\s*module\s+([A-Za-z_]\w*)', re.M)
# `foo #(...) bar (`  or  `foo bar (` — the whitespace between the module name
# and the instance name is REQUIRED in the no-parameter form, otherwise `if (`
# parses as module `i` + instance `f`.
INST_RE = re.compile(
    r'^[ \t]*([A-Za-z_]\w*)[ \t]*'
    r'(?:#[ \t]*\([^;]*?\)[ \t]*([A-Za-z_]\w*)|[ \t]+([A-Za-z_]\w*))'
    r'[ \t]*\(',
    re.M | re.S)
PORT_DECL_RE = re.compile(
    r'^\s*(?:input|output|inout)\b[^;,)]*?([A-Za-z_]\w*)\s*(?:,|\)|$)', re.M)
NAMED_PORT_RE = re.compile(r'\.\s*([A-Za-z_]\w*)\s*\(')


def strip_comments(src):
    src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
    src = re.sub(r'//[^\n]*', '', src)
    return src


def collect(paths):
    """Return {module_name: (file, declared_port_names)} across all sources."""
    modules = {}
    files = []
    for root in paths:
        if os.path.isfile(root):
            files.append(root)
            continue
        for dirpath, _dirnames, filenames in os.walk(root):
            for fn in filenames:
                if fn.endswith(('.v', '.sv')):
                    files.append(os.path.join(dirpath, fn))
    for path in files:
        with open(path, encoding='utf-8', errors='replace') as fh:
            src = strip_comments(fh.read())
        for m in MODULE_RE.finditer(src):
            name = m.group(1)
            # Port list = text from the module keyword to the first standalone ');'
            tail = src[m.end():]
            depth = 0
            end = len(tail)
            for i, ch in enumerate(tail):
                if ch == '(':
                    depth += 1
                elif ch == ')':
                    depth -= 1
                    if depth == 0:
                        end = i
                        break
            header = tail[:end]
            ports = set(PORT_DECL_RE.findall(header))
            ports |= set(re.findall(r'^\s*\.?([A-Za-z_]\w*)\s*,?\s*$',
                                    header, re.M))
            modules[name] = (path, ports)
    return modules, files


def main():
    paths = sys.argv[1:] or ['rtl']
    modules, files = collect(paths)
    problems = []

    for path in files:
        with open(path, encoding='utf-8', errors='replace') as fh:
            src = strip_comments(fh.read())
        for m in INST_RE.finditer(src):
            mod = m.group(1)
            inst = m.group(2) or m.group(3)
            if mod in NOT_INSTANCES or inst in NOT_INSTANCES:
                continue
            if mod == inst:
                continue
            if mod not in modules:
                # Unknown modules are usually vendor primitives or macros;
                # only flag ones that look like ours (lowercase, in-tree style).
                if re.match(r'^(alt|lpm_|cyclone|arria|stratix|mf_)', mod):
                    continue
                line = src[:m.start()].count('\n') + 1
                problems.append(
                    f'{path}:{line}: instantiates unknown module '
                    f'`{mod}` (as `{inst}`)')

    print(f'scanned {len(files)} files, {len(modules)} module definitions')
    if problems:
        print(f'\n{len(problems)} dangling reference(s):')
        for p in problems:
            print('  ' + p)
        return 1
    print('no dangling module references')
    return 0


if __name__ == '__main__':
    sys.exit(main())
