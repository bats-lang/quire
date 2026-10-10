#!/usr/bin/env python3
"""A choice of more than three is a menu, not a button that cycles it
(quire#377: the sort button went round five orders, four taps to Series
and four back). A function named `*_next` that takes a datatype and gives
the same datatype is that button's: it is refused when the datatype has
more than three constructors.

usage: tests/static/next.py <src-dir>...   (exit 1 on any finding)
"""
import re
import sys
from pathlib import Path

MOST = 3
# The reader's running footer is tapped to go round what it reads out
# (pages left, page of pages, chapter, time left in chapter and in book),
# as the Kindle apps' footer goes round location, page and time left: a
# readout shown in place, not a setting that is chosen, so it is not a menu
ALLOWED = {'_readout_next'}
DATATYPE = re.compile(r'datatype\s+(\w+)\s*=([^()]*?)(?=\n\s*\n|\n\(\*|\n#|\nfn |\nfun |\nval |\nimplement )', re.S)
NEXT = re.compile(r'\bfn\s+(\w*_next)\s*\(\s*\w+\s*:\s*(\w+)\s*\)\s*:\s*(\w+)')


def constructors(body):
    return len(re.findall(r'(?:^|\|)\s*[A-Z]\w*', body))


def main(dirs):
    files = [f for d in dirs for f in sorted(Path(d).rglob('*.bats'))]
    text = {f: re.sub(r'\(\*.*?\*\)', '', f.read_text(), flags=re.S) for f in files}
    sizes = {}
    for source in text.values():
        for name, body in DATATYPE.findall(source):
            sizes[name] = constructors(body)
    found = 0
    for f, source in text.items():
        for name, taken, given in NEXT.findall(source):
            if taken == given and sizes.get(taken, 0) > MOST and name not in ALLOWED:
                print(f'{f}: {name} cycles {taken}, which has {sizes[taken]} constructors: make it a menu')
                found += 1
    print(f'{found} cycling function(s)')
    return 1 if found else 0


sys.exit(main(sys.argv[1:]))
