#!/usr/bin/env python3
"""A static fixture finds its edit by a marker, not by prose (quire#983, keyword:
fixture anchors). `before` is the line the snippet is put in front of: a comment
there must be a marker line `(* fixture: <name> *)`, kept for that purpose, so a
reworded comment (or a keyword added to it) does not break the fixture; any other
line (a function's name) is fine. With a second argument, the checkout, the line
must also be in the fixture's `file`, and no occurrence of it there may be a line
inside a block comment (a continuation line is as fragile as the first line).

Why this is not bats (quire#646): bats's `bats fixtures` (bats#267) checks only that
some line of `file` equals `before`; it has no option to judge what kind of line that
is, and no bats package matches text: repository-prototype has no regex or glob
package, and tools/text-lint's pattern language (src/pattern.bats) is a program for
pull request bodies, with no call to read a module's comments. Searched:
repository-prototype's package list and tools/, bats's fixtures.md and
src/fixtures.bats. The move is bats-lang/bats, "bats fixtures refuses a `before`
that is a line of a comment without the marker" (bats-lang/bats#577); this checker is a stopgap
deleted when that lands.

usage: anchors.py <dir with accept/ and reject/> [<checkout>]
"""
import os
import re
import sys

MARKER = re.compile(r'^\s*\(\* fixture: [a-z0-9]+(-[a-z0-9]+)* \*\)$')


def comment_lines(text):
    """The lines that are inside a block comment or open one, `(* ... *)` nesting as ATS's do."""
    inside, depth = set(), 0
    for number, line in enumerate(text.split('\n')):
        if depth > 0 or line.lstrip().startswith('(*'):
            inside.add(line)
        i = 0
        while i < len(line) - 1:
            pair = line[i:i + 2]
            if pair == '(*':
                depth += 1
                i += 2
            elif pair == '*)' and depth > 0:
                depth -= 1
                i += 2
            else:
                i += 1
    return inside


def findings(fixtures, checkout):
    found, count = [], 0
    for verdict in ('accept', 'reject'):
        base = os.path.join(fixtures, verdict)
        for name in sorted(os.listdir(base)) if os.path.isdir(base) else []:
            d = os.path.join(base, name)
            if not os.path.isfile(os.path.join(d, 'before')):
                continue
            count += 1
            before = open(os.path.join(d, 'before')).read().rstrip('\n')
            refused = len(found)
            if before.lstrip().startswith('(*') and not MARKER.match(before):
                found.append(f'{verdict}/{name}: `before` is a comment with no marker: {before!r}'
                             ' (put `(* fixture: <name> *)` above it and anchor on that)')
            if checkout:
                path = os.path.join(checkout, open(os.path.join(d, 'file')).read().strip())
                text = open(path).read()
                if before not in text.split('\n'):
                    found.append(f'{verdict}/{name}: no line of {path} equals `before`: {before!r}')
                elif len(found) == refused and before in comment_lines(text) and not MARKER.match(before):
                    found.append(f'{verdict}/{name}: `before` is a line of a comment with no marker: {before!r}'
                                 ' (put `(* fixture: <name> *)` above the comment and anchor on that)')
    return found, count


def main():
    found, count = findings(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
    for line in found:
        print(line)
    print(f'{count} fixtures, {len(found)} refused')
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main())
