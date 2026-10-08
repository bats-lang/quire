#!/usr/bin/env python3
"""Fails when the library's keys are named outside src/libstore.bats.

The library's records (`library/...`) are written only by libstore, which
reads a record before it changes it (#354): any other module naming such a
key could put a put or an update beside it.

usage: tests/static/keys.py <src dir>
"""
import re
import sys
from pathlib import Path


def main(root):
    found = []
    for path in sorted(Path(root).rglob('*.bats')):
        if path.name == 'libstore.bats':
            continue
        for number, line in enumerate(path.read_text().split('\n'), 1):
            stripped = re.sub(r'\(\*.*?\*\)', ' ', line)
            if re.search(r'"library/', stripped):
                found.append(f'{path}:{number}: {line.strip()}')
    for item in found:
        print(item)
    print(f'{len(found)} use(s) of a library key outside libstore.bats' if found else 'no library key outside libstore.bats')
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
