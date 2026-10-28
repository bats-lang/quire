#!/usr/bin/env python3
"""A static fixture finds its edit by a marker, not by prose (quire#983, keyword:
fixture anchors). `before` is the line the snippet is put in front of: a comment
there must be a marker line `(* fixture: <name> *)`, kept for that purpose, so a
reworded comment (or a keyword added to it) does not break the fixture; any other
line (a function's name) is fine. With a second argument, the checkout, the line
must also be in the fixture's `file`.

usage: anchors.py <dir with accept/ and reject/> [<checkout>]
"""
import os
import re
import sys

MARKER = re.compile(r'^\s*\(\* fixture: [a-z0-9]+(-[a-z0-9]+)* \*\)$')


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
            if before.lstrip().startswith('(*') and not MARKER.match(before):
                found.append(f'{verdict}/{name}: `before` is a comment with no marker: {before!r}'
                             ' (put `(* fixture: <name> *)` above it and anchor on that)')
            if checkout:
                path = os.path.join(checkout, open(os.path.join(d, 'file')).read().strip())
                if before not in open(path).read().split('\n'):
                    found.append(f'{verdict}/{name}: no line of {path} equals `before`: {before!r}')
    return found, count


def main():
    found, count = findings(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
    for line in found:
        print(line)
    print(f'{count} fixtures, {len(found)} refused')
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main())
