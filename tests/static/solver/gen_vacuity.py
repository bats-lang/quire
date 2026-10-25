#!/usr/bin/env python3
"""Writes the fixtures that show a flagged context is not contradictory (quire#840 and #841, pieces of #594).

proofs_audit.py flags the places where the solver's context can get contradictory, and every flagged
place has a verdict (tests/static/proofs_audit_verdicts.txt) naming the fixtures written here. A
fixture is the proof that contains the flagged place, with what it uses, copied from the text of the
module or of the locked package (proof_sources.py), and one change that makes a claim false
inside the flagged context. A context that is contradictory proves any claim, so the solver would
accept the change; it must reject it, and reject/<fixture>.expect says where. The same text without
the change is accept/<fixture>.dats, the control.

Two kinds of change (patsopt reports the first unsolved constraint of a file, so a change has to be
the first claim that is false):
  probe      `prval _ : [t == t + 1] void = ()` put in the flagged branch, t a term of the flagged
             line that holds a division: the facts of the division and the branch's hypotheses are in
             the context of that claim
  statement  the proof's own result, one index plus one, for a proof whose body is only the flagged
             lines: the first claim that is then false is the last one, which has every division
             of the body in it
  context    the flagged lines of a function that has no copy (an `implement`), as a `prfn` with
             the function's own variables and guards and the type of its result, plus one
             in an index

usage: gen_vacuity.py [--lock bats.lock] [--repository DIR] [--check]
"""
import argparse
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parent))
import proof_sources as sources  # noqa: E402

ARITH = 'arith:src/lib.bats'


def probe(term):
    return f'prval _ : [{term} == {term} + 1] void = ()'


def wrap(term, expression):
    return f'(let {probe(term)} in {expression} end)'


def in_expression(term, expression, count=1):
    return (expression, wrap(term, expression), count)


SPECS = []  # (fixture, module, roots, changes, extra, why)


def add(fixture, module, roots, changes, why, extra=None):
    SPECS.append((fixture, module, roots, changes, extra, why))


# ---- src/crc.bats ----
add('vacuity-crc-xor-exists-even-even', 'src/crc.bats', ['xor_exists'],
    [in_expression('left/2 + right/2', 'xor_double(xor_exists{left/2,right/2}())')],
    'both numbers even, in xor_exists (src/crc.bats:333)')
add('vacuity-crc-xor-exists-even-odd', 'src/crc.bats', ['xor_exists'],
    [in_expression('left/2 + right/2', 'XOR_01(xor_exists{left/2,right/2}())')],
    'left even and right odd, in xor_exists (src/crc.bats:334)')
add('vacuity-crc-xor-exists-odd-even', 'src/crc.bats', ['xor_exists'],
    [in_expression('left/2 + right/2', 'XOR_10(xor_exists{left/2,right/2}())')],
    'left odd and right even, in xor_exists (src/crc.bats:336)')
add('vacuity-crc-xor-exists-odd-odd', 'src/crc.bats', ['xor_exists'],
    [in_expression('left/2 + right/2', 'XOR_11(xor_exists{left/2,right/2}())')],
    'both numbers odd, in xor_exists (src/crc.bats:337)')
add('vacuity-crc-step1-exists-low-even', 'src/crc.bats', ['step1_exists'],
    [in_expression('high/2 + low/2', 'STEP1_even{high/2, high - 2*(high/2), low/2}()')],
    'an even low half, in step1_exists (src/crc.bats:347)')
add('vacuity-crc-step1-exists-low-odd-xor', 'src/crc.bats', ['step1_exists'],
    [('prval [low_xored:int] low_proof', probe('low/2') + '\n    prval [low_xored:int] low_proof', 1)],
    'an odd low half, before the xor of the low half, in step1_exists (src/crc.bats:351)')
add('vacuity-crc-step1-exists-low-odd-result', 'src/crc.bats', ['step1_exists'],
    [in_expression('high/2 + low/2', 'STEP1_odd{high/2, high - 2*(high/2), low/2, high_xored, low_xored}(high_proof, low_proof)')],
    'an odd low half, at the result, in step1_exists (src/crc.bats:353)')
add('vacuity-crc-shift2-first', 'src/crc.bats', ['shift2'],
    [in_expression('r/2', 'STEP1_even{2*h + r/2, r - 2*(r/2), 2*l}()')],
    'the first step of shift2 (src/crc.bats:380)')
add('vacuity-crc-shift2-second', 'src/crc.bats', ['shift2'],
    [in_expression('r/2', 'STEP1_even{h, r/2, l + 16384*(r - 2*(r/2))}()')],
    'the second step of shift2 (src/crc.bats:381)')
add('vacuity-crc-shift4-first', 'src/crc.bats', ['shift4'],
    [in_expression('r/4', 'shift2{4*h + r/4, r - 4*(r/4), 4*l}()')],
    'the first half of shift4 (src/crc.bats:386)')
add('vacuity-crc-shift4-second', 'src/crc.bats', ['shift4'],
    [in_expression('r/4', 'shift2{h, r/4, l + 4096*(r - 4*(r/4))}()')],
    'the second half of shift4 (src/crc.bats:386)')
add('vacuity-crc-shift8-first', 'src/crc.bats', ['shift8'],
    [in_expression('r/16', 'shift4{16*h + r/16, r - 16*(r/16), 16*l}()')],
    'the first half of shift8 (src/crc.bats:391)')
add('vacuity-crc-shift8-second', 'src/crc.bats', ['shift8'],
    [in_expression('r/16', 'shift4{h, r/16, l + 256*(r - 16*(r/16))}()')],
    'the second half of shift8 (src/crc.bats:391)')

# ---- arith (the locked package) ----
for lemma in ('xor_zero_right', 'xor_zero_left', 'xor_self'):
    add(f'vacuity-arith-{lemma.replace("_", "-")}', ARITH, [lemma],
        [in_expression('a/2', 'xor_double(go{a/2}())')],
        f'the even case of go, in {lemma} (arith src/lib.bats)')
for branch in ('XOR_00', 'XOR_01', 'XOR_10', 'XOR_11'):
    add(f'vacuity-arith-xor-half-{branch.lower().replace("_", "-")}', ARITH, ['xor_half'],
        [(f'| {branch}(p1) => p1', f'| {branch}(p1) => ' + wrap('a/2 + b/2 + c/2', 'p1'), 1)],
        f'the {branch} case of xor_half (arith src/lib.bats:220)')
STATEMENTS = [
    ('rotr_digits_2', 'ROTR(2, 4*a + r, 4*b + t, a + 16384*t, b + 16384*r)', 'ROTR(2, 4*a + r, 4*b + t, a + 16384*t + 1, b + 16384*r)'),
    ('rotr_digits_4', 'ROTR(4, 16*a + r, 16*b + t, a + 4096*t, b + 4096*r)', 'ROTR(4, 16*a + r, 16*b + t, a + 4096*t + 1, b + 4096*r)'),
    ('rotr_digits_8', 'ROTR(8, 256*a + r, 256*b + t, a + 256*t, b + 256*r)', 'ROTR(8, 256*a + r, 256*b + t, a + 256*t + 1, b + 256*r)'),
    ('rotr_by_16', 'ROTR(16, h, l, l, h)', 'ROTR(16, h, l, l, h + 1)'),
    ('shr_digits_2', 'SHR(2, 4*a + r, 4*b + t, a, b + 16384*r)', 'SHR(2, 4*a + r, 4*b + t, a, b + 16384*r + 1)'),
    ('shr_digits_4', 'SHR(4, 16*a + r, 16*b + t, a, b + 4096*r)', 'SHR(4, 16*a + r, 16*b + t, a, b + 4096*r + 1)'),
    ('shr_digits_8', 'SHR(8, 256*a + r, 256*b + t, a, b + 256*r)', 'SHR(8, 256*a + r, 256*b + t, a, b + 256*r + 1)'),
    ('shr_by_16', 'SHR(16, h, l, 0, h)', 'SHR(16, h, l, 0, h + 1)'),
]
for lemma, old, new in STATEMENTS:
    add(f'vacuity-arith-{lemma.replace("_", "-")}', ARITH, [lemma], [(old, new, 1)],
        f'the result of {lemma} one more: its first and second steps are built with every division of the body (arith src/lib.bats)')


def step_context(kind, bits, false):
    """The static content of rotr_step_<bits> or shr_step_<bits>: the lemma with the divisions by 2^bits,
    cast to the halves of the function, as a prfn (arith src/lib.bats)."""
    span, rest_span = 1 << bits, 1 << (16 - bits)
    high = f'h/{span} + {rest_span}*(l - {span}*(l/{span}))' if kind == 'rotr' else f'h/{span}'
    low = f'l/{span} + {rest_span}*(h - {span}*(h/{span}))'
    if false:
        low = low + ' + 1'
    return (f'prfn {kind}_step_{bits}_context {{h,l:nat | h < 65536; l < 65536}} ()\n'
            f'  : {kind.upper()}({bits}, h, l, {high}, {low}) =\n'
            f'  {kind}_cast({kind}_digits_{bits}{{h/{span}, l/{span}, h - {span}*(h/{span}), l - {span}*(l/{span})}}())\n')


CONTEXTS = [(kind, bits) for kind in ('rotr', 'shr') for bits in (1, 2, 4, 8)]


def build(world, spec, false, context=None):
    fixture, module, roots, changes, extra, why = spec
    blocks = [b for name in roots for b in world.named(name, module)]
    if not blocks:
        raise KeyError(f'{roots} not in {module}')
    kind = 'Change' if false else 'Control, the same text unchanged'
    header = (f'(* {module} {", ".join(roots)}, copied: see gen_vacuity.py.\n'
              f'   {kind}: {why} *)\n')
    return sources.fixture_text(world, blocks, header, changes if false else ())


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument('--lock', default=str(ROOT / 'bats.lock'))
    parser.add_argument('--repository', default=os.environ.get('BATS_REPOSITORY'))
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args(argv)
    world = sources.World(ROOT, args.lock, args.repository)
    files = {}
    for spec in SPECS:
        for kind in ('accept', 'reject'):
            files[HERE / kind / f'{spec[0]}.dats'] = build(world, spec, kind == 'reject')
    for kind, bits in CONTEXTS:
        name = f'vacuity-arith-{kind}-step-{bits}'
        roots = [b for n in (f'{kind}_digits_{bits}', f'{kind}_cast') for b in world.named(n, ARITH)]
        for verdict in ('accept', 'reject'):
            false = verdict == 'reject'
            header = (f'(* {ARITH} {kind}_digits_{bits}, {kind}_cast, copied: see gen_vacuity.py.\n'
                      f'   {"Change: the second half of the result one more" if false else "Control, the same text unchanged"}:'
                      f' the static content of {kind}_step_{bits}, which has no copy (arith src/lib.bats) *)\n')
            files[HERE / verdict / f'{name}.dats'] = sources.fixture_text(world, roots, header) + '\n' + step_context(kind, bits, false)
    bad = 0
    for path, text in sorted(files.items()):
        if args.check:
            if not path.exists() or path.read_text() != text:
                print(f'FAIL {path.relative_to(ROOT)} is not what the sources give now: run gen_vacuity.py')
                bad += 1
        else:
            path.write_text(text)
    if args.check:
        for path in sorted(list((HERE / 'reject').glob('vacuity-*.dats')) + list((HERE / 'accept').glob('vacuity-*.dats'))):
            if path not in files and not path.name.startswith('vacuity-by-hand-'):
                print(f'FAIL {path.relative_to(ROOT)} is no fixture of a spec')
                bad += 1
        print(f'{len(SPECS) + len(CONTEXTS)} vacuity specs, {len(files)} fixtures checked, {bad} differ')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
