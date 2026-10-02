#!/usr/bin/env python3
"""Every match is a case+, checked for exhaustiveness: ATS2 checks only
case+ (a plain case warns, case- not even that), so a plain case could
leave out a constructor unseen (bats-lang/quire#192). Prints each plain
case in the .bats files under the given directory, outside comments and
strings, and fails when there is one.

usage: case_plus.py <dir>
"""
import os
import re
import sys


def code_only(text):
    """text with its comments and string and char literals blanked,
    keeping its lines"""
    out = []
    i, n, depth = 0, len(text), 0
    while i < n:
        c = text[i]
        if depth > 0:
            if text.startswith('(*', i):
                depth += 1; out.append('  '); i += 2
            elif text.startswith('*)', i):
                depth -= 1; out.append('  '); i += 2
            else:
                out.append('\n' if c == '\n' else ' '); i += 1
        elif text.startswith('(*', i):
            depth = 1; out.append('  '); i += 2
        elif text.startswith('//', i):
            while i < n and text[i] != '\n':
                out.append(' '); i += 1
        elif c == '"':
            out.append(' '); i += 1
            while i < n and text[i] != '"':
                if text[i] == '\\':
                    out.append(' '); i += 1
                out.append('\n' if i < n and text[i] == '\n' else ' '); i += 1
            out.append(' '); i += 1
        elif c == "'" and i + 2 < n and text[i + 2] == "'":
            out.append('   '); i += 3
        else:
            out.append(c); i += 1
    return ''.join(out)


PLAIN = re.compile(r'(?<![\w$])case(?![\w+])')


def main(root):
    found = 0
    for dirpath, _, files in sorted(os.walk(root)):
        for name in sorted(files):
            if not name.endswith('.bats'):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding='utf-8') as f:
                code = code_only(f.read())
            for number, line in enumerate(code.split('\n'), 1):
                if PLAIN.search(line):
                    print(f'{path}:{number}: a plain case (use case+): {line.strip()}')
                    found += 1
    print(f'{found} plain case(s)')
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
