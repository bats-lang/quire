#!/usr/bin/env python3
"""What the error banner says is a failure with a next step (quire#360):
the words are made in one place, notice.bats, from a `failure` and a
`remedy` by total matches, so no other module may put a string in the
banner (`notice_error(`, `notice_error_buf(`), and a failure of the
archive is matched case by case, never with a wildcard
(`ArchiveFailed(_)`), so a new cause has to be said. Prints each such
line in the .bats files under the given directory and fails when there
is one.

usage: notice.py <dir>
"""
import os
import re
import sys

STRING_IN_BANNER = re.compile(r'\bnotice_error(_buf)?\(')
WILDCARD = re.compile(r'ArchiveFailed\(_\)')


def main(root):
    found = 0
    for directory, _, names in os.walk(root):
        for name in sorted(names):
            if not name.endswith('.bats'):
                continue
            path = os.path.join(directory, name)
            with open(path, encoding='utf-8') as source:
                for number, line in enumerate(source, 1):
                    if name != 'notice.bats' and STRING_IN_BANNER.search(line):
                        print(f'{path}:{number}: a string put in the error banner outside notice.bats: {line.strip()}')
                        found += 1
                    if WILDCARD.search(line):
                        print(f'{path}:{number}: an archive failure matched with a wildcard: {line.strip()}')
                        found += 1
    print(f'{found} banner(s) without a failure')
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
