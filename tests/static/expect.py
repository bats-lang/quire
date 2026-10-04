#!/usr/bin/env python3
"""Whether a reject fixture failed exactly as it says it must.

A reject fixture's `expect` names the proof or check its snippet breaks:

    function <the snippet's function the error is in>
    line <the line of snippet.bats patsopt reports it at>
    <patsopt's error, as it says it: its message after "error(N): " and
     the lines it adds (the case left out, the terms that differ, ...)>

bats check of the fixture's copy must fail with exactly that: patsopt's
errors all in the module the snippet is put in (`file`), at that line of
the snippet, inside that function, and their text, line for line, that
text (patsopt reports one mistake as more than one error at times: a
type that does not match, then the terms that differ). Nothing else
fails. A substring that another error could also hold is not enough.

patsopt numbers its variables as it goes (S2EVar(16274->...),
S2Evar(count(11804)), handed$6116), so a change anywhere before the
snippet renumbers them: those numbers, and only those, are compared as
"_".

usage: tests/static/expect.py <fixture dir> <bats check log> <line of
       `file` the snippet's first line is at>
"""
import os
import re
import sys

HEADER = re.compile(
    r'^(?P<path>\S+\.bats): \d+\(line=(?P<line>\d+), offs=\d+\) -- '
    r'\d+\(line=\d+, offs=\d+\): error\(\d+\): (?P<message>.*)$')
# What ends an error's added lines: patsopt's summary, its exit, bats's
# own lines
AFTER = re.compile(r'^(typechecking has failed|exit\(ATS\)|patsopt\(|error:|warning:|built |check )')
DECLARATION = re.compile(
    r'^(?:fn|fun|fnx|prfn|prfun|implement|val|var|and)\s+'
    r'(?:\{[^}]*\}\s*)*(?P<name>[A-Za-z_][A-Za-z0-9_$]*)')


NUMBERS = [
    (re.compile(r'S2EVar\(\d+->'), 'S2EVar(_->'),
    # a dynamic variable: [handed$6116(-1)]
    (re.compile(r'\$\d+\('), '$_('),
    # a static variable: S2Evar(count(11804)); a constant, S2Eintinf(2),
    # keeps its number
    (re.compile(r'S2Evar\(([A-Za-z_][A-Za-z0-9_]*)\(\d+\)\)'), r'S2Evar(\1(_))'),
]


def unnumbered(text):
    """text with patsopt's variable numbers as "_"."""
    for pattern, replacement in NUMBERS:
        text = pattern.sub(replacement, text)
    return text


def errors(log):
    """patsopt's errors in the log: (path, line, text lines)."""
    found = []
    current = None
    for line in log.splitlines():
        header = HEADER.match(line)
        if header:
            current = (header['path'], int(header['line']), [header['message']])
            found.append(current)
        elif current is not None and not AFTER.match(line) and line.strip():
            current[2].append(line)
        else:
            current = None
    return found


def enclosing(snippet_lines, line):
    """The name of the snippet's top-level declaration that holds line
    (1-based), or None."""
    name = None
    for text in snippet_lines[:line]:
        declared = DECLARATION.match(text)
        if declared:
            name = declared['name']
    return name


def main(fixture, log_path, first_line):
    with open(os.path.join(fixture, 'expect')) as expect_file:
        expect = expect_file.read().rstrip('\n').split('\n')
    with open(os.path.join(fixture, 'file')) as file_file:
        module = file_file.read().strip()
    with open(os.path.join(fixture, 'snippet.bats')) as snippet_file:
        snippet = snippet_file.read().split('\n')
    with open(log_path, errors='replace') as log_file:
        log = log_file.read()
    if len(expect) < 3 or not expect[0].startswith('function ') or not expect[1].startswith('line '):
        return 'its expect is not "function <name>", "line <n>", then the error'
    function = expect[0][len('function '):].strip()
    line = int(expect[1][len('line '):])
    text = expect[2:]
    if enclosing(snippet, line) != function:
        return f'line {line} of its snippet is not in {function}'
    found = errors(log)
    if not found:
        return 'no error of patsopt\'s'
    got = []
    for path, at, lines in found:
        if not path.endswith('/' + module):
            return f'an error is in {path}, not {module}: {lines[0]}'
        snippet_line = at - first_line + 1
        if snippet_line != line:
            return f'an error is at line {snippet_line} of its snippet, not {line}: {lines[0]}'
        got += lines
    if [unnumbered(x) for x in got] != [unnumbered(x) for x in text]:
        return 'its error is not the one expected:\n' + '\n'.join(got)
    return None


if __name__ == '__main__':
    problem = main(sys.argv[1], sys.argv[2], int(sys.argv[3]))
    if problem:
        print(problem)
        sys.exit(1)
