#!/usr/bin/env python3
"""Writes a reject fixture for each luminance constant of src/palette_proofs.bats (quire#837, piece of #594).

`prval L_<rrggbb> = $CT.LUMc(...)` states nothing in its own text: its type, LUM(colour, low, high), is
what css's constructor LUMc gives for the three channels' LIN witnesses, and `mutation_check.py` reads
lemmas, not these constants. The false variants of a constant state the bound it has plus one, the low and
the high one, over the same LUMc term, copied with css's LIN and LUM from the locked css package
(proof_sources.py); the solver must reject both (reject/luminance-<rrggbb>-low-bound-plus-one.dats and -high-, with their .expect: patsopt reports the first unsolved constraint of a file only, so one false statement is a fixture).
The true statements of all the constants are accept/luminance-palette-constants.dats, the control: the
bounds here are computed from css's table independently of the solver, so a rejection is the +1's.
`--check` fails when a constant has no fixture, a fixture has no constant, or a file differs.

usage: gen_luminance.py [--lock bats.lock] [--repository DIR] [--check]
"""
import argparse
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parent))
import proof_sources as sources  # noqa: E402

CONSTANT = re.compile(r'^prval L_([0-9a-f]{6}) = \$CT\.LUMc\(\$CT\.LIN_([0-9a-f]{2})\(\), \$CT\.LIN_([0-9a-f]{2})\(\), \$CT\.LIN_([0-9a-f]{2})\(\)\)$', re.M)


def constants(root):
    """[(rrggbb, (r, g, b hex channels))] of src/palette_proofs.bats, each checked against its own name."""
    out = []
    for m in CONSTANT.finditer((Path(root) / 'src/palette_proofs.bats').read_text()):
        colour, channels = m.group(1), m.groups()[1:]
        if colour != ''.join(channels):
            raise ValueError(f'L_{colour} is built from the channels {channels}')
        out.append((colour, channels))
    return out


def bounds(table, channels):
    r, g, b = (table[c] for c in channels)
    return (2126 * r[0] + 7152 * g[0] + 722 * b[0], 2126 * r[1] + 7152 * g[1] + 722 * b[1])


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument('--lock', default=str(ROOT / 'bats.lock'))
    parser.add_argument('--repository', default=os.environ.get('BATS_REPOSITORY'))
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args(argv)
    world = sources.World(ROOT, args.lock, args.repository)
    css = 'css:src/contrast.bats'
    roots = world.named('LIN', css) + world.named('LUM', css)
    base = sources.fixture_text(world, roots, '')
    table = {c: (int(lo), int(hi)) for c, lo, hi in
             ((h, lo, hi) for h, _, lo, hi in re.findall(r'\| LIN_([0-9a-f]{2})\((\d+), (\d+), (\d+)\)', base))}
    if len(table) != 256:
        raise ValueError(f'css gives {len(table)} LIN witnesses, not 256')
    files = {}
    true = []
    for colour, channels in constants(ROOT):
        low, high = bounds(table, channels)
        term = 'LUMc(' + ', '.join(f'LIN_{c}()' for c in channels) + ')'
        value = int(colour, 16)
        true.append(f'prval _ : LUM({value}, {low}, {high}) = {term}')
        for which, statement in (('low', f'LUM({value}, {low + 1}, {high})'), ('high', f'LUM({value}, {low}, {high + 1})')):
            header = (f'(* css LIN and LUM, copied: see gen_luminance.py. False variant of L_{colour} (src/palette_proofs.bats):\n'
                      f'   the {which} bound plus one *)\n')
            text = header.join(['#include "share/atspre_staload.hats"\n', base.split('\n', 1)[1]])
            files[HERE / 'reject' / f'luminance-{colour}-{which}-bound-plus-one.dats'] = text + f'\nprval _ : {statement} = {term}\n'
    header = '(* css LIN and LUM, copied: see gen_luminance.py. The true bounds of every L_ constant of src/palette_proofs.bats *)\n'
    files[HERE / 'accept' / 'luminance-palette-constants.dats'] = (
        header.join(['#include "share/atspre_staload.hats"\n', base.split('\n', 1)[1]]) + '\n' + '\n'.join(true) + '\n')
    bad = 0
    for path, text in sorted(files.items()):
        if args.check:
            if not path.exists() or path.read_text() != text:
                print(f'FAIL {path.relative_to(ROOT)} is not what the constants give now: run gen_luminance.py')
                bad += 1
        else:
            path.write_text(text)
    if args.check:
        for path in sorted((HERE / 'reject').glob('luminance-*.dats')):
            if path not in files:
                print(f'FAIL {path.relative_to(ROOT)} is the fixture of no constant')
                bad += 1
        print(f'{(len(files) - 1) // 2} luminance constants, {len(files)} fixtures checked, {bad} differ')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
