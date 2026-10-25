#!/usr/bin/env python3
"""Writes a reject fixture for each lemma whose result no mutation operator reaches (quire#838, piece of #594).

`mutation_check.py` makes a false variant of a lemma by changing the arguments of its result type.
A lemma that concludes FALSEP(), an EQFD, a tuple or a bare existential has no argument to change,
so it makes no mutant, and a lemma whose premises had become contradictory (or whose FALSEP could
be built) would type-check and prove nothing. Each fixture here is the lemma with its own body, and
everything the body uses, copied from the text of the module (proof_sources.py), under a statement
that is false: the premises of a FALSEP lemma are made satisfiable by shifting a guard by one, the
conclusion of the others is changed. The solver must reject it (reject/lemma-<name>.dats, with its
.expect). The same text without the change is written to accept/lemma-<name>.dats as the control,
so the rejection is the change's and not a typo of the copy.

usage: gen_lemmas.py [--lock bats.lock] [--repository DIR] [--check]   (any directory)
  --check  writes nothing; fails when a fixture differs from what the modules give now, or is missing
"""
import argparse
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parent))
import proof_sources as sources  # noqa: E402

FALSEP_SATISFIABLE = ('impossible < 0; impossible > 0}', 'impossible < 2; impossible > 0}', 1)

# fixture, module, the lemmas it covers, the changes (old, new, times), why the result is false
SPECS = [
    ('contradiction', 'bytes', ['contradiction'],
     [('impossible < 0; impossible > 0} (): FALSEP()', 'impossible < 0} (): FALSEP()', 1)],
     'a FALSEP made at a value only below zero: the guard that makes it unbuildable is dropped'),
    ('take-not-short', 'bytes', ['take_not_short', '_take_not_short'],
     [('SHORT(count, octets)): FALSEP()', 'SHORT(count + 1, octets)): FALSEP()', 2)],
     'octets short of count + 1 bytes can have count bytes to take'),
    ('take-append', 'bytes', ['take_append', '_take_append'],
     [('LEN(taken, count))', 'LEN(taken, count + 1))', 2)],
     'what is taken is count long, not one more'),
    ('append-assoc', 'bytes', ['append_assoc', '_append_assoc'],
     [('APPEND(first, second_third, all))', 'APPEND(second_third, first, all))', 2)],
     'first is not after second_third in all'),
    ('append-assoc-rev', 'bytes', ['append_assoc_rev', '_append_assoc_rev'],
     [('APPEND(first, second, first_second), APPEND(first_second, third, all))',
       'APPEND(second, first, first_second), APPEND(first_second, third, all))', 2)],
     'second is not after first in first_second'),
    ('lenok-not-big', 'chunk', ['lenok_not_big'],
     [('length_high >= 16}', 'length_high >= 15}', 1)],
     'a length with a third byte of 15 and no fourth is both small and big'),
    ('known-not-notknown', 'schema', ['known_not_notknown', '_known_not_notknown'],
     [('left_fourth != right_fourth}', 'left_fourth != right_fourth || 0 == 0}', 1)],
     'two tags that TAGDIFF calls different can be equal'),
    ('anc-not-crit', 'schema', ['anc_not_crit'],
     [('97 <= first_letter', '96 <= first_letter', 1)],
     'a tag with the first letter 96 is both ancillary and critical'),
    ('loses-not-added', 'schema', ['_loses_not_added'],
     [('needed: LOSES(m_added())', 'needed: LOSES(m_opt())', 1)],
     'an optional group can be lost'),
    ('allgood-bad-false', 'seq', ['allgood_bad_false'],
     [('ALLGOOD(chunk_count, pbad(tag, chunks))', 'ALLGOOD(chunk_count, pgood(tag, tag, chunks))', 1)],
     'a list that begins with a good chunk is all good'),
    ('falsep-eqfd', 'fields', ['falsep_eqfd'],
     [FALSEP_SATISFIABLE],
     'a FALSEP that can be built (guard shifted past zero) does not give any two results equal'),
    ('fdec-functional', 'fields', ['fdec_functional', '_fdec_functional'],
     [('FDEC(kinds, octets, right_result)): EQFD(left_result, right_result)',
       'FDEC(kinds, octets, right_result)): EQFD(left_result, fd_bad())', 2)],
     'a reading that comes to fd_ok does not come to fd_bad'),
]


def build(world, spec, false):
    name, module, lemmas, changes, why = spec
    roots = [b for lemma in lemmas for b in world.named(lemma, f'src/{module}.bats')]
    if not roots:
        raise KeyError(f'{lemmas} not in src/{module}.bats')
    kind = 'False variant' if false else 'Control, the same text as reject/lemma-' + name + '.dats unchanged'
    header = (f'(* quire src/{module}.bats {", ".join(lemmas)}, copied: see gen_lemmas.py.\n'
              f'   {kind}{": " + why if false else ""} *)\n')
    return sources.fixture_text(world, roots, header, changes if false else ())


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument('--lock', default=str(ROOT / 'bats.lock'))
    parser.add_argument('--repository', default=os.environ.get('BATS_REPOSITORY'))
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args(argv)
    world = sources.World(ROOT, args.lock, args.repository)
    bad = 0
    expected = {'accept': set(), 'reject': set()}
    for spec in SPECS:
        for kind in ('accept', 'reject'):
            path = HERE / kind / f'lemma-{spec[0]}.dats'
            expected[kind].add(path.name)
            text = build(world, spec, kind == 'reject')
            if args.check:
                if not path.exists() or path.read_text() != text:
                    print(f'FAIL {path.relative_to(ROOT)} is not what the modules give now: run gen_lemmas.py')
                    bad += 1
            else:
                path.write_text(text)
    if args.check:
        for kind in ('accept', 'reject'):
            for path in sorted((HERE / kind).glob('lemma-*.dats')):
                if path.name not in expected[kind]:
                    print(f'FAIL {path.relative_to(ROOT)} is no fixture of a spec')
                    bad += 1
        print(f'{len(SPECS)} lemma specs, {2 * len(SPECS)} fixtures checked, {bad} differ')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
