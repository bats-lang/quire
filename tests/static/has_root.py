#!/usr/bin/env python3
"""No selector in the stylesheet's rules asks :has() of an ancestor of the
chapter (quire#538, #423): Blink re-evaluates a :has() whose subject is
#bats-root, .rv, .caf or body over the whole subtree at every change of
the page's chrome (16 to 27 ms a change on a 5 MB chapter, four times a
page turn). The view says the state in a class or a data attribute
instead (banner_place_set, ui_banner_under_menu). Prints the file and
line of each such selector in src/*_rules.bats and src/ui.bats, and fails
when there is one.

usage: has_root.py <dir>
"""
import os
import re
import sys

# the compound selector just before ':has(' (back to a space, '>', '+',
# '~', ',' or the opening quote)
SUBJECT = re.compile(r'([^\s>+~,"\']*):has\(')
ANCESTOR = re.compile(r'(#bats-root|\.rv\b|\.caf\b|^body\b|^html\b|^:root\b)')


def main(root):
    found = 0
    for directory, _, names in os.walk(root):
        for name in sorted(names):
            if not (name.endswith('_rules.bats') or name == 'ui.bats'):
                continue
            path = os.path.join(directory, name)
            with open(path, encoding='utf-8') as source:
                for number, line in enumerate(source, 1):
                    for match in SUBJECT.finditer(line):
                        if ANCESTOR.search(match.group(1)):
                            print(f'{path}:{number}: :has() on {match.group(1)}, an ancestor of the chapter: {line.strip()}')
                            found += 1
    print(f'{found} :has() selector(s) on an ancestor of the chapter')
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
