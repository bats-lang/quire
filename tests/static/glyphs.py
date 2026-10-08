#!/usr/bin/env python3
"""No button's text holds the chevron U+203A (quire#361): it would be part
of the button's accessible name (WCAG 2.5.3, label in name), and a row
that opens a screen gets its chevron from the stylesheet (`.chev::after`,
drawn with an empty alternative text), not from its words. Prints each
ui_text_btn( line in the .bats files under the given directory whose text
has it, and fails when there is one.

usage: glyphs.py <dir>
"""
import os
import re
import sys

BUTTON = re.compile(r'ui_text_btn\(')
CHEVRON = re.compile(r'(\\xE2\\x80\\xBA|\\u203[Aa]|›)')


def main(root):
    found = 0
    for directory, _, names in os.walk(root):
        for name in sorted(names):
            if not name.endswith('.bats'):
                continue
            path = os.path.join(directory, name)
            with open(path, encoding='utf-8') as source:
                for number, line in enumerate(source, 1):
                    if BUTTON.search(line) and CHEVRON.search(line):
                        print(f'{path}:{number}: a chevron in a button\'s text: {line.strip()}')
                        found += 1
    print(f'{found} chevron(s) in button text')
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
