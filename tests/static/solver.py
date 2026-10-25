#!/usr/bin/env python3
"""Runs the solver fixtures (tests/static/solver/{accept,reject}/*.dats) with a patsopt (#594).

Each fixture is one ATS file that needs only the prelude: an accept fixture
is a TRUE statement and must type-check; a reject fixture is a FALSE one and
must fail with an unsolved constraint (or a type mismatch). They exercise
the constraint solver on the shapes of the proofs here (digit-form numbers,
nested division, two scales, products of variables, FALSEP, guards, tuples,
existentials) and are the list to run under any solver build (the 32-bit
one and an infinite-precision one): nothing here knows quire.

A reject fixture is also exact (quire#837): <name>.expect, beside it, says what its rejection is,
one block for each error patsopt reports, in order, blocks apart by a blank line:

    line <the line of the fixture patsopt reports>
    function <the prfun, prfn, primplement or prval the line is in>
    <patsopt's error after "error(3): ", and the lines it adds to it>

and the fixture passes only when its errors are exactly those (patsopt's warnings are not errors
and are not compared; its variable numbers, which move with any line above, are compared as "_").
A reject fixture with no expect, or whose errors differ, fails: a statement that is rejected for a
reason other than the one it names (a typo in the copy) is not the false variant it says.

usage: tests/static/solver.py [--ats-home DIR] [--dir DIR] [--known FILE] [--record] [--only TEXT]... [--quiet]
   --only TEXT   only the fixtures whose `accept/<name>` or `reject/<name>` holds TEXT (any of the texts given)
   --quiet       prints the failures and the count only
   --known FILE  fixture names (accept/x, reject/y) a build is known to get wrong: reported, not failed
   --record      writes the .expect of each reject fixture from what patsopt says now (to read, then commit)
   DIR defaults to ~/.bats/ats2 (its bin/patsopt is run with PATSHOME=DIR)
"""
import os
import re
import subprocess
import sys
from pathlib import Path

ERROR = re.compile(r'^(?P<path>\S+\.dats): \d+\(line=(?P<line>\d+), offs=\d+\) -- \d+\(line=\d+, offs=\d+\): error\((?P<kind>\w+)\): (?P<message>.*)$')
OTHER = re.compile(r'^(?:\S+\.dats: \d+\(line=|typechecking has failed|exit\(ATS\)|patsopt\()')
DECLARATION = re.compile(r"^(?:extern\s+)?(?:prfun|prfn|primplement|prval|fun|fn|implement|val|dataprop)\s+(?:\{[^}]*\}\s*)*([A-Za-z_][\w']*)")
# patsopt numbers its variables as it goes, so a line above the error moves them
NUMBERS = [
    (re.compile(r'S2EVar\(\d+->'), 'S2EVar(_->'),
    (re.compile(r'S2EVar\(\d+\)'), 'S2EVar(_)'),
    (re.compile(r'\$\d+(?:\$\d+)*(?:\(-?\d+\))?'), '$_'),
    (re.compile(r'S2Evar\(([A-Za-z_][\w\']*)\(\d+\)\)'), r'S2Evar(\1(_))'),
    (re.compile(r'S2Evar\(([A-Za-z_][\w\']*)\$\d+(?:\$\d+)*\(\d+\)\)'), r'S2Evar(\1(_))'),
]


def unnumbered(text):
    for pattern, replacement in NUMBERS:
        text = pattern.sub(replacement, text)
    return text


def errors_of(path, out):
    """[(line, function, message)] of the errors patsopt printed for the fixture at `path`."""
    lines = path.read_text().split('\n')
    found, current = [], None
    for text in out.split('\n'):
        m = ERROR.match(text)
        if m:
            current = [int(m.group('line')), m.group('message')]
            found.append(current)
        elif OTHER.match(text):
            current = None
        elif current is not None and text.strip():
            current[1] += '\n' + text
    result = []
    for line, message in found:
        function = '-'
        for back in range(min(line, len(lines)) - 1, -1, -1):
            d = DECLARATION.match(lines[back])
            if d:
                function = d.group(1)
                break
        result.append((line, function, unnumbered(message)))
    return result


def expect_text(errors):
    return '\n\n'.join(f'line {line}\nfunction {function}\n{message}' for line, function, message in errors) + '\n'


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
    only = []
    it = iter(argv)
    for a in it:
        if a == '--ats-home':
            home = next(it)
        elif a == '--dir':
            root = Path(next(it))
        elif a == '--known':
            known = set(Path(next(it)).read_text().split())
        elif a == '--record':
            record = True
        elif a == '--only':
            only.append(next(it))
        elif a == '--quiet':
            quiet = True
    known = locals().get('known', set())
    quiet = locals().get('quiet', False)
    record = locals().get('record', False)
    failed = 0
    count = 0
    for kind in ('accept', 'reject'):
        for path in sorted((root / kind).glob('*.dats')):
            if only and not any(text in f'{kind}/{path.stem}' for text in only):
                continue
            count += 1
            accepted, out = verdict(home, path)
            if accepted is None:
                failed += 1
                print(f'FAIL {kind}/{path.stem}: broken fixture (not a type or constraint error): ' + out.strip().splitlines()[0][:160])
            elif accepted == (kind == 'accept'):
                expect = path.with_suffix('.expect')
                if kind == 'reject' and record:
                    expect.write_text(expect_text(errors_of(path, out)))
                if kind == 'accept':
                    (quiet or print(f'ok   {kind}/{path.stem}'))
                elif not expect.exists():
                    failed += 1
                    print(f'FAIL {kind}/{path.stem}: rejected, but it has no {expect.name} saying how')
                elif expect.read_text() != expect_text(errors_of(path, out)):
                    failed += 1
                    print(f'FAIL {kind}/{path.stem}: rejected, but not as {expect.name} says; patsopt says:')
                    print(expect_text(errors_of(path, out)))
                else:
                    (quiet or print(f'ok   {kind}/{path.stem}'))
            elif f'{kind}/{path.stem}' in known:
                print(f'KNOWN {kind}/{path.stem} (the solver of this build is unsound here)')
            else:
                failed += 1
                print(f'FAIL {kind}/{path.stem}: ' + ('accepted a false statement' if accepted else 'rejected a true statement: ' + out.strip().splitlines()[0][:160]))
    print(f'{count} fixtures, {failed} failed')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
