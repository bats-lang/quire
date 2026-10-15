#!/usr/bin/env python3
"""Lists the arithmetic in proofs that can make the 32-bit solver's context
contradictory (#594).

The constraint solver does 32-bit arithmetic: when elimination overflows, the
context becomes contradictory and anything is proved, a false statement
included. This happened with no large literal at all (nested divisions,
`h/256 + 256*(l mod 256)`, arith's rotation), so tests/static/literals.py
cannot see it. This audit reads the statements of proofs (prfun, prfn,
primplement, praxi, prval, dataprop, dataview, stadef, absprop, and the
static quantifiers `{..}` of everything else) and reports, with a severity:

  HIGH    nested         two or more `/` or `mod` in one line
  HIGH    var-divisor    `/` or `mod` by something that is not a literal
  HIGH    nonlinear      a product of two terms neither of which is a literal
  MEDIUM  const-coeff    a product by a NAMED_CONSTANT: linear, its value is the coefficient
  HIGH    wide-literal   a literal or product of literals of over 2^28 (2^28 itself is MEDIUM, edge-2^28)
  MEDIUM  wide-coeff     a literal or product of literals of 2^16 to 2^28
  MEDIUM  wide-divisor   `/` or `mod` by a literal over 16 (the rule is 16 at a time)
  LOW     divides        one `/` or `mod` by a literal of at most 16

It is a list for a human and for the mutation checker (mutation_check.py),
which is what decides whether a flagged lemma proves anything: a line here is
a place to look, not a verdict.

usage: tests/static/proofs_audit.py [--summary] [--fail-on high|medium|low] [--lock bats.lock
         --repository DIR] <dir-or-file-or-zip>...
  a directory is searched for *.bats; a zip (a published package) is read for
  its src/*.bats; --lock with --repository adds the packages the lock names.
"""
import re
import sys
import zipfile
from pathlib import Path

PROOF_START = re.compile(
    r'^\s*(?:#pub\s+)?(?:prfun|prfn|primplement|praxi|prval|dataprop|dataview|'
    r'stadef|absprop|propdef|sortdef|datasort)\b', re.M)
DECL = re.compile(
    r'\b(?:prfun|prfn|primplement|praxi|prval|dataprop|dataview|stadef|absprop)\s+'
    r'(?:\{[^}]*\}\s*)*([A-Za-z_][\w\']*)')
NUMBER = re.compile(r'(?<![\w$.])(0x[0-9a-fA-F]+|\d+)(?![\w.])')
RANK = {'HIGH': 3, 'MEDIUM': 2, 'LOW': 1}


def strip(text):
    """The text without comments (nested) and strings, line count kept."""
    out = []
    depth = 0
    i = 0
    while i < len(text):
        two = text[i:i + 2]
        if two == '(*' and not text.startswith('(*)', i):
            depth += 1
            i += 2
        elif two == '*)' and depth:
            depth -= 1
            i += 2
        elif depth:
            out.append('\n' if text[i] == '\n' else ' ')
            i += 1
        elif text[i] == '"':
            j = i + 1
            while j < len(text) and text[j] != '"':
                j += 2 if text[j] == '\\' else 1
            seg = text[i:j + 1]
            out.append(''.join(c if c == '\n' else ' ' for c in seg))
            i = j + 1
        else:
            out.append(text[i])
            i += 1
    return ''.join(out)


def value(token):
    return int(token, 16) if token.startswith('0x') else int(token)


def operand_before(line, pos):
    j = pos
    while j > 0 and line[j - 1] == ' ':
        j -= 1
    if j and line[j - 1] == ')':
        depth = 0
        while j > 0:
            j -= 1
            depth += (line[j] == ')') - (line[j] == '(')
            if depth == 0:
                break
        return line[j:pos].strip()
    m = re.search(r"[\w']+$", line[:j])
    return m.group(0) if m else ''


def operand_after(line, pos):
    j = pos
    while j < len(line) and line[j] == ' ':
        j += 1
    if j < len(line) and line[j] == '(':
        depth = 0
        k = j
        while k < len(line):
            depth += (line[k] == '(') - (line[k] == ')')
            k += 1
            if depth == 0:
                break
        return line[j:k].strip()
    m = re.match(r"[\w']+", line[j:])
    return m.group(0) if m else ''


def is_literal(text):
    return bool(re.fullmatch(r'\(?\s*(0x[0-9a-fA-F]+|\d+)\s*\)?', text))


def literal_value(text):
    return value(re.search(r'0x[0-9a-fA-F]+|\d+', text).group(0))


def analyse(line):
    """Findings of one line of statement: (severity, kind, detail)."""
    found = []
    ops = [m for m in re.finditer(r'(?<![\w])mod(?![\w])|(?<![/*(=<])/(?![/*)=>])', line)]
    if len(ops) >= 2:
        found.append(('HIGH', 'nested', f'{len(ops)} divisions in one line'))
    for m in ops:
        divisor = operand_after(line, m.end())
        if not divisor:
            continue
        if not is_literal(divisor):
            found.append(('HIGH', 'var-divisor', f'{m.group(0)} {divisor}'))
        elif literal_value(divisor) > 16:
            found.append(('MEDIUM', 'wide-divisor', f'{m.group(0)} {divisor}'))
        elif len(ops) == 1:
            found.append(('LOW', 'divides', f'{m.group(0)} {divisor}'))
    for m in re.finditer(r'(?<![(*])\*(?![*)])', line):
        left, right = operand_before(line, m.start()), operand_after(line, m.end())
        if left and right and not is_literal(left) and not is_literal(right):
            if re.fullmatch(r'[A-Z][A-Z0-9_]*', left) or re.fullmatch(r'[A-Z][A-Z0-9_]*', right):
                # a named constant: linear, but its value is the coefficient
                found.append(('MEDIUM', 'const-coeff', f'{left} * {right}'))
            else:
                found.append(('HIGH', 'nonlinear', f'{left} * {right}'))
    # a chain of literal factors multiplies: 256 * 256 * x
    for m in re.finditer(r'(?:(?:0x[0-9a-fA-F]+|\d+)\s*\*\s*)+(?:0x[0-9a-fA-F]+|\d+)', line):
        product = 1
        for t in re.findall(r'0x[0-9a-fA-F]+|\d+', m.group(0)):
            product *= value(t)
        if product > 1 << 28:
            found.append(('HIGH', 'wide-literal', m.group(0)))
        elif product >= 1 << 16:
            found.append(('MEDIUM', 'wide-coeff', m.group(0)))
    for m in NUMBER.finditer(line):
        v = value(m.group(1))
        if v > 1 << 28:
            found.append(('HIGH', 'wide-literal', m.group(1)))
        elif v == 1 << 28:
            found.append(('MEDIUM', 'edge-2^28', m.group(1)))
        elif v >= 1 << 16 and not re.search(r'\*', line[max(0, m.start() - 3):m.end() + 3]):
            found.append(('MEDIUM', 'wide-coeff', m.group(1)))
    seen, unique = set(), []
    for item in found:
        if item not in seen:
            seen.add(item)
            unique.append(item)
    return unique


def statements(text):
    """(line number, name, line) of the lines that state a proof."""
    lines = strip(text).split('\n')
    chunks, start = [], 0
    for index, line in enumerate(lines + ['']):
        if not line.strip():
            if start < index:
                chunks.append((start, index))
            start = index + 1
    for first, last in chunks:
        block = '\n'.join(lines[first:last])
        proof = bool(PROOF_START.search(block))
        name = ''
        for offset in range(first, last):
            m = DECL.search(lines[offset])
            if m:
                name = m.group(1)
            line = lines[offset]
            if proof:
                yield offset + 1, name, line
            else:
                # only static quantifiers: {a:int | ...} or [a | ...]
                for q in re.finditer(r'\{[^{}]*[:|][^{}]*\}|\[[^\[\]]*\|[^\[\]]*\]', line):
                    yield offset + 1, name, q.group(0)


def audit(label, text):
    results = []
    for number, name, line in statements(text):
        for severity, kind, detail in analyse(line):
            results.append((label, number, name, severity, kind, detail, line.strip()))
    return results


def sources(arguments):
    for argument in arguments:
        path = Path(argument)
        if path.is_dir():
            for f in sorted(path.rglob('*.bats')):
                if 'build' in f.parts or '.git' in f.parts:
                    continue
                yield str(f), f.read_text(errors='replace')
        elif zipfile.is_zipfile(path):
            with zipfile.ZipFile(path) as z:
                for member in sorted(z.namelist()):
                    if member.endswith('.bats') and member.startswith('src/'):
                        yield f'{path.name}:{member}', z.read(member).decode(errors='replace')
        elif path.is_file():
            yield str(path), path.read_text(errors='replace')


def locked(lock, repository):
    for entry in Path(lock).read_text().split('\n'):
        parts = entry.split()
        if len(parts) < 2:
            continue
        name, version = parts[0], parts[1]
        flat = name.replace('/', '_')
        for candidate in (Path(repository) / f'{flat}_{version}.bats',
                          Path(repository) / name.split('/')[-1] / f'{name.split("/")[-1]}_{version}.bats'):
            if candidate.exists():
                yield str(candidate)
                break
        else:
            print(f'# not in the repository: {name} {version}', file=sys.stderr)


def main(argv):
    fail_on, lock, repository, targets, summary = None, None, None, [], False
    it = iter(argv)
    for a in it:
        if a == '--fail-on':
            fail_on = next(it).upper()
        elif a == '--summary':
            summary = True
        elif a == '--lock':
            lock = next(it)
        elif a == '--repository':
            repository = next(it)
        else:
            targets.append(a)
    if lock:
        targets += list(locked(lock, repository))
    results = []
    for label, text in sources(targets):
        results += audit(label, text)
    results.sort(key=lambda r: (-RANK[r[3]], r[0], r[1]))
    if summary:
        groups = {}
        for label, number, name, severity, kind, detail, line in results:
            g = groups.setdefault((label, name or '-', severity), {'lines': [], 'kinds': set()})
            g['lines'].append(number)
            g['kinds'].add(kind)
        for (label, name, severity), g in sorted(groups.items(), key=lambda kv: (-RANK[kv[0][2]], kv[0][0], kv[0][1])):
            lines = sorted(set(g['lines']))
            print(f'{severity:6} {label} {name}: {",".join(sorted(g["kinds"]))} at {",".join(map(str, lines[:6]))}{"..." if len(lines) > 6 else ""}')
    else:
      for label, number, name, severity, kind, detail, line in results:
        print(f'{severity:6} {kind:13} {label}:{number} {name or "-"}: {detail}   | {line[:100]}')
    counts = {s: sum(1 for r in results if r[3] == s) for s in RANK}
    print(f'{counts["HIGH"]} high, {counts["MEDIUM"]} medium, {counts["LOW"]} low')
    if fail_on and any(RANK[r[3]] >= RANK[fail_on] for r in results):
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
