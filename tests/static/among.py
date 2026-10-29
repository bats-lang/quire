#!/usr/bin/env python3
"""A reject fixture's expect names the one constructor it is about (quire#984, keyword:
fixture among). patsopt names each unmatched constructor of a nonexhaustive match in an
error of its own, so an `expect` that lists them line for line breaks when a constructor is
added to the datatype, however far from the fixture. `bats fixtures` takes the form

    function <name>
    line <n>
    pattern match is nonexhaustive:
    among <Constructor>

(bats-lang/bats#573), which passes while the constructor is among the unmatched ones. This
lint refuses an `expect` that says `pattern match is nonexhaustive` in any other way: with
the constructors listed line for line (one, which breaks as soon as another is added, or
several), or with more than one `among` line.

Why this is not bats (quire#646): `bats fixtures` accepts both forms of an expect (the old
one is kept by the overlap rule, a test of bats calls it) and has no option to refuse one;
no bats package matches text (what anchors.py searched: repository-prototype's package list
and tools/, bats's fixtures.md and src/fixtures.bats; the `among` section of fixtures.md
was read again for this). The same stopgap as anchors.py, deleted when bats judges the
expects of a directory of fixtures.

usage: among.py <dir with accept/ and reject/> -- each <name>/expect under reject/ is read;
       a tree of the checker's own fixtures holds reject/<case>/reject/<name>/expect.
"""
import os
import sys

HEADER = 'pattern match is nonexhaustive:'


def problem(expect):
    """Why an expect that says nonexhaustive is not the `among` form, or None."""
    if 'pattern match is nonexhaustive' not in expect:
        return None
    lines = expect.rstrip('\n').split('\n')
    rest = lines[2:]
    amongs = [line for line in rest if line.startswith('among ')]
    listed = [line for line in rest if not line.startswith(('pattern match is nonexhaustive', 'among ')) and line != '']
    if len(amongs) > 1:
        return f'{len(amongs)} `among` lines: a fixture is about one constructor'
    if listed:
        return (f'lists {len(listed)} constructor(s) of a nonexhaustive match line for line '
                f'({", ".join(listed)}): adding a constructor to the datatype breaks it; '
                'write `among <Constructor>` for the one it is about')
    if not amongs:
        return 'a nonexhaustive match without an `among <Constructor>` line'
    if rest != [HEADER, amongs[0]]:
        return f'the lines after `line <n>` are not exactly `{HEADER}` and `among <Constructor>`'
    if not amongs[0][len('among '):].strip():
        return '`among` names no constructor'
    return None


def findings(fixtures):
    found, count = [], 0
    base = os.path.join(fixtures, 'reject')
    for name in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        path = os.path.join(base, name, 'expect')
        if not os.path.isfile(path):
            continue
        count += 1
        why = problem(open(path).read())
        if why:
            found.append(f'reject/{name}: {why}')
    return found, count


def main():
    found, count = findings(sys.argv[1])
    for line in found:
        print(line)
    print(f'{count} expects, {len(found)} refused')
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main())
