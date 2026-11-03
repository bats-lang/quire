#!/usr/bin/env python3
"""Fails when e2e/ holds a fixed wait for a step whose duration depends on the runner, or a
quarantine mark that names no ticket (quire#976, keyword: fixed-wait, quarantine).

* A fixed wait is `waitForTimeout(` or a sleep, `setTimeout(` whose first argument is a bare
  function (`setTimeout(r, 500)`, `setTimeout(resolve, 500)`, `setTimeout(() => resolve(), 500)`).
  `test.setTimeout(` (a test's budget) and a timer with a body of its own (a limit, a page's
  own code) are not sleeps. A wait is for an event, with a limit that is the test's budget.
* The waits that exist today are listed in tests/static/e2e_waits_allowed.tsv, one line for each
  file: `path<TAB>count<TAB>#ticket`. The ticket is the one that migrates them; the count is
  exact, so a new wait fails and a migrated one lowers the count (a count above the file's
  waits fails too, so the list only shrinks).
* A test failure that gets a p0 ticket is marked `test.fixme('#N ...', ...)` in the commit
  that files it, on every project: the mark names its ticket, and holds no condition but `true`.

usage: tests/static/e2e_waits.py [ROOT]   (ROOT holds e2e/ and tests/static/e2e_waits_allowed.tsv)
Exit 0 when clean, 1 with one line for each finding.

Stopgap (CLAUDE.md, "Pipeline and tooling improvements belong in bats or pwa"): a second app
with a Playwright suite would copy this lint; the avenue exhausted for non-bats code
(quire#646): bats has no command that reads JavaScript, and the suite it lints is JavaScript.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ALLOWED = 'tests/static/e2e_waits_allowed.tsv'
WAIT_FOR_TIMEOUT = re.compile(r'\bwaitForTimeout\s*\(')
# setTimeout( not preceded by a dot (test.setTimeout is a budget), its first argument a name or an arrow that only resolves
# a delay of 0 is a yield to the event loop, not a wait (`setTimeout(spinForever, 0)` in the page code of a fixture)
# the callback may have a braced body that only resolves: `() => { resolve(); }` (a sleep under another spelling, quire#976)
RESOLVER = r'(?:r|res|resolve|done|ok|fulfill)'
SLEEP = re.compile(r'(?<![.\w])setTimeout\s*\(\s*(?:[A-Za-z_$][\w$]*\s*,|\(\s*\)\s*=>\s*(?:' + RESOLVER + r'\s*\(\s*\)|\{\s*' + RESOLVER + r'\s*\(\s*\)\s*;?\s*\})\s*,)(?!\s*0\s*[,)])')
# the one span helper: `const lasting = (ms) => new Promise(...)`, defined once in e2e/; its calls are listed as spans
# a timer whose handle is kept (`limit = setTimeout(...)`) is a limit when the handle is cleared within CLEARED_WITHIN lines
# of it (`clearTimeout(limit)`, the event came first); a kept handle never cleared (`nap = setTimeout(r, 5000)`) is a sleep
KEPT = re.compile(r'([\w$]+)\s*=\s*setTimeout\s*\(')
CLEARED_WITHIN = 15
SPAN_DEFINITION = re.compile(r'\bconst\s+lasting\s*=')
SPAN_CALL = re.compile(r'(?<![.\w])lasting\s*\(([^)]*)\)')
FIXME = re.compile(r'\.fixme\s*\(')
FIXME_GOOD = re.compile(r'\.fixme\s*\(\s*(?:true\s*,\s*)?([\'"`])[^\n]*#\d+')
TICKET = re.compile(r'(?:[\w.-]+/[\w.-]+)?#\d+')


def code_of(line):
    """The line without a trailing // comment (a mention of the call in a comment is not a call)."""
    stripped = line.lstrip()
    if stripped.startswith(('//', '*', '/*')):
        return ''
    return line


def sources(root):
    base = os.path.join(root, 'e2e')
    for directory, names, files in os.walk(base):
        names[:] = sorted(name for name in names if name != 'node_modules')
        for name in sorted(files):
            if name.endswith(('.js', '.mjs', '.cjs')):
                yield os.path.relpath(os.path.join(directory, name), root)


def cleared(lines, number, code):
    """True when the line keeps its timer's handle and clears it within CLEARED_WITHIN lines either side."""
    kept = KEPT.search(code)
    if not kept:
        return False
    clear = re.compile(r'\bclearTimeout\s*\(\s*' + re.escape(kept.group(1)) + r'\s*\)')
    return any(clear.search(code_of(line)) for line in lines[max(number - 1 - CLEARED_WITHIN, 0):number + CLEARED_WITHIN])


def waits_of(text):
    """(line number, line) of each fixed wait. The definition of the span helper is not one (spans_of lists its calls)."""
    found = []
    lines = text.split('\n')
    for number, line in enumerate(lines, 1):
        code = code_of(line)
        if WAIT_FOR_TIMEOUT.search(code) or (SLEEP.search(code) and not SPAN_DEFINITION.search(code) and not cleared(lines, number, code)):
            found.append((number, line.strip()))
    return found


def spans_of(text):
    """(line number, argument) of each call of the span helper, and the number of its definitions."""
    calls, definitions = [], 0
    for number, line in enumerate(text.split('\n'), 1):
        code = code_of(line)
        if SPAN_DEFINITION.search(code):
            definitions += 1
        else:
            calls.extend((number, match.group(1).strip()) for match in SPAN_CALL.finditer(code))
    return calls, definitions


def load_allowed(root):
    allowed, findings = {}, []
    path = os.path.join(root, ALLOWED)
    if not os.path.exists(path):
        return allowed, [f'{ALLOWED}: missing']
    with open(path, encoding='utf-8') as handle:
        for number, line in enumerate(handle, 1):
            if not line.strip() or line.startswith('#'):
                continue
            fields = line.rstrip('\n').split('\t')
            if len(fields) != 3 or not fields[1].isdigit() or not TICKET.fullmatch(fields[2]):
                findings.append(f'{ALLOWED}:{number}: a line is `path<TAB>count<TAB>#ticket` (an entry cites the ticket that migrates it)')
            elif fields[0] in allowed:
                findings.append(f'{ALLOWED}:{number}: {fields[0]} is listed twice')
            else:
                allowed[fields[0]] = (int(fields[1]), fields[2])
    return allowed, findings


def lint(root):
    allowed, findings = load_allowed(root)
    seen = {}
    spans = []
    defined = []
    total = 0
    for relative in sources(root):
        with open(os.path.join(root, relative), encoding='utf-8') as handle:
            text = handle.read()
        calls, definitions = spans_of(text)
        spans.extend((relative, number, argument) for number, argument in calls)
        defined.extend([relative] * definitions)
        waits = waits_of(text)
        total += len(waits)
        seen[relative] = len(waits)
        permitted = allowed.get(relative, (0, ''))[0]
        if len(waits) > permitted:
            for number, line in waits[permitted:] if permitted else waits:
                findings.append(f'{relative}:{number}: a fixed wait ({line[:80]}): wait for an event with the test\'s budget as the limit (quire#976); {len(waits)} wait(s) in the file, {permitted} listed in {ALLOWED}')
        elif len(waits) < permitted:
            findings.append(f'{ALLOWED}: {relative} lists {permitted} wait(s) and has {len(waits)}: lower the count to {len(waits)} (the list only shrinks)')
        for number, line in enumerate(text.split('\n'), 1):
            code = code_of(line)
            if FIXME.search(code) and not FIXME_GOOD.search(code):
                findings.append(f'{relative}:{number}: a quarantine mark is `test.fixme(\'#N what fails\', ...)` (or `test.fixme(true, \'#N ...\')` in the body): it names its ticket and holds no condition but true, so it holds on every project (quire#976)')
    for relative in allowed:
        if relative not in seen:
            findings.append(f'{ALLOWED}: {relative} is not a file of e2e/: drop the line')
    if len(defined) > 1:
        findings.append(f'the span helper `lasting` is defined {len(defined)} times ({", ".join(defined)}): one definition, imported (quire#976)')
    return findings, total, seen, spans


def main(arguments):
    root = arguments[0] if arguments else os.path.dirname(os.path.dirname(HERE))
    findings, total, seen, spans = lint(root)
    for finding in findings:
        print(finding)
    if not findings:
        print(f'ok: {total} fixed wait(s) in {sum(1 for count in seen.values() if count)} file(s) of e2e/, all listed with their ticket')
    for relative, number, argument in spans:
        print(f'span: {relative}:{number}: lasting({argument}) (an instrument\'s own duration or cadence, not a wait for a step)')
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
