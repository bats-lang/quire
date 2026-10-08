#!/usr/bin/env python3
"""Fails on an integer literal of 2 to the 29 or more in the app's sources.

The constraint solver does 32-bit arithmetic: a constant or a coefficient
of 2 to the 30 or more in a hypothesis makes the context contradictory, and
anything is then proved (#354). Nothing in src/ needs one in a proof; a
literal that is only a run-time value (a size, a limit, the edge of 32
bits) is marked by `(* wide *)` on its line.

usage: tests/static/literals.py <src dir>
"""
import re
import sys
from pathlib import Path

LIMIT = 1 << 29
NUMBER = re.compile(r'(?<![\w$.])(0x[0-9a-fA-F]+|\d+)(?![\w.])')


def code(line):
    """The line without its comments and strings."""
    line = re.sub(r'\(\*.*?\*\)', ' ', line)
    line = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
    return line


def main(root):
    found = []
    for path in sorted(Path(root).rglob('*.bats')):
        in_comment = 0
        for number, line in enumerate(path.read_text().split('\n'), 1):
            if '(* wide *)' in line:
                continue
            stripped = code(line)
            # a comment spanning lines
            if in_comment:
                if '*)' in stripped:
                    stripped = stripped.split('*)', 1)[1]
                    in_comment = 0
                else:
                    continue
            if '(*' in stripped:
                stripped = stripped.split('(*', 1)[0]
                in_comment = 1
            for match in NUMBER.finditer(stripped):
                text = match.group(1)
                value = int(text, 16) if text.startswith('0x') else int(text)
                if value >= LIMIT:
                    found.append(f'{path}:{number}: {text}')
    for item in found:
        print(item)
    print(f'{len(found)} literal(s) of 2 to the 29 or more' if found else 'no literal of 2 to the 29 or more')
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
