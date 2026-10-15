#!/usr/bin/env python3
"""Runs the solver fixtures (tests/static/solver/{accept,reject}/*.dats) with a patsopt (#594).

Each fixture is one ATS file that needs only the prelude: an accept fixture
is a TRUE statement and must type-check; a reject fixture is a FALSE one and
must fail with an unsolved constraint (or a type mismatch). They exercise
the constraint solver on the shapes of the proofs here (digit-form numbers,
nested division, two scales, products of variables, FALSEP, guards, tuples,
existentials) and are the list to run under any solver build (the 32-bit
one and an infinite-precision one): nothing here knows quire.

usage: tests/static/solver.py [--ats-home DIR] [--dir DIR] [--known FILE]
   --known FILE  fixture names (accept/x, reject/y) a build is known to get wrong: reported, not failed
   DIR defaults to ~/.bats/ats2 (its bin/patsopt is run with PATSHOME=DIR)
"""
import os
import subprocess
import sys
from pathlib import Path


def verdict(home, path):
    done = subprocess.run([f'{home}/bin/patsopt', '-tc', '-d', str(path)], capture_output=True, text=True,
                          env={**os.environ, 'PATSHOME': home})
    out = done.stdout + done.stderr
    import re
    kinds = set(re.findall(r'error\((\w+)\)', out))
    # a reject fixture must fail by the solver or the types (error(3)), not by a missing file
    # or a syntax error, which would reject anything
    if kinds - {'3'}:
        return None, out
    return ('typechecking has failed' not in out and not kinds), out


def main(argv):
    home = os.path.expanduser('~/.bats/ats2')
    root = Path(__file__).resolve().parent / 'solver'
    it = iter(argv)
    for a in it:
        if a == '--ats-home':
            home = next(it)
        elif a == '--dir':
            root = Path(next(it))
        elif a == '--known':
            known = set(Path(next(it)).read_text().split())
    known = locals().get('known', set())
    failed = 0
    count = 0
    for kind in ('accept', 'reject'):
        for path in sorted((root / kind).glob('*.dats')):
            count += 1
            accepted, out = verdict(home, path)
            if accepted is None:
                failed += 1
                print(f'FAIL {kind}/{path.stem}: broken fixture (not a type or constraint error): ' + out.strip().splitlines()[0][:160])
            elif accepted == (kind == 'accept'):
                print(f'ok   {kind}/{path.stem}')
            elif f'{kind}/{path.stem}' in known:
                print(f'KNOWN {kind}/{path.stem} (the solver of this build is unsound here)')
            else:
                failed += 1
                print(f'FAIL {kind}/{path.stem}: ' + ('accepted a false statement' if accepted else 'rejected a true statement: ' + out.strip().splitlines()[0][:160]))
    print(f'{count} fixtures, {failed} failed')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
