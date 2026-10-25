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
a place to look, not a verdict. The verdict of each HIGH row is written down in
tests/static/proofs_audit_verdicts.txt (quire#840, #841), and `--fail-on high`
passes only when every HIGH row has one:

  scope | file | proof | kind | fixtures | reason

scope is `quire` for src/ and the package's name for a locked package; file
is its path in src/; proof is the declaration the row is in (`xor_exists`, the
`implement` or `fun` of a function); kind is the row's kind. fixtures name the
reject fixtures of tests/static/solver/ (their .dats and .expect must exist)
that put a false claim in that context, which the solver rejects, so the context is not
contradictory: `a, b`; or an `issue:<url>` that restructures it. A row whose
key is not in the file has no verdict. The row's own lines are in the output.

usage: tests/static/proofs_audit.py [--summary] [--keys] [--fail-on high|medium|low]
         [--verdicts FILE] [--lock bats.lock --repository DIR] <dir-or-file-or-zip>...
  --keys  prints one line for each key of the HIGH rows (its rows' lines and its verdict), not each row
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


CONTINUATION = re.compile(r'^(?:in|end|and|then|else|with)\b')
PROOF_LINE = re.compile(
    r'^\s*(?:#pub\s+)?(?:prfun|prfn|primplement|praxi|prval|dataprop|dataview|'
    r'stadef|absprop|propdef|sortdef|datasort)\b')
TOP_DECLARATION = re.compile(
    r"^(?:#pub\s+)?(?:prfun|prfn|primplement|praxi|prval|dataprop|dataview|stadef|absprop|"
    r"implement|fun|fn|fnx|val|and)\s+(?:\{[^}]*\}\s*)*([A-Za-z_][\w']*)")


def indent(line):
    return len(line) - len(line.lstrip())


def proof_lines(lines):
    """Which lines are in a proof construct: a line that begins one (a prfun, a prval ...) and the lines
    after it that are indented more (or continue it: `in`, `end`). A prval in the body of a function does not
    make the lines after it proof (quire#841: gestures' tracker.bats, a pinch's arithmetic on plain ints)."""
    marked, start = [False] * len(lines), None
    for index, line in enumerate(lines):
        if not line.strip():
            marked[index] = start is not None
            continue
        if start is not None and (indent(line) > start or (start == 0 and CONTINUATION.match(line))):
            marked[index] = True
            continue
        start = indent(line) if PROOF_LINE.match(line) else None
        marked[index] = start is not None
    return marked


def enclosing(lines, number):
    """The name of the declaration at the left margin that line `number` (1-based) is in, or '-'."""
    for index in range(number - 1, -1, -1):
        m = TOP_DECLARATION.match(lines[index])
        if m:
            return m.group(1)
    return '-'


def statements(text):
    """(line number, name, line) of the lines that state a proof."""
    lines = strip(text).split('\n')
    marked = proof_lines(lines)
    name = ''
    for offset, line in enumerate(lines):
        m = DECL.search(line)
        if m:
            name = m.group(1)
        if marked[offset]:
            yield offset + 1, name, line
        else:
            # only static quantifiers: {a:int | ...} or [a | ...]
            for q in re.finditer(r'\{[^{}]*[:|][^{}]*\}|\[[^\[\]]*\|[^\[\]]*\]', line):
                yield offset + 1, name, q.group(0)


def audit(label, text):
    results = []
    lines = strip(text).split('\n')
    for number, name, line in statements(text):
        for severity, kind, detail in analyse(line):
            results.append((label, number, name, severity, kind, detail, line.strip(), enclosing(lines, number)))
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
                          Path(repository) / name.split('/')[-1] / f'{name.split("/")[-1]}_{version}.bats',
                          # a namespaced package: wasm.bats-packages.dev/bridge/wasm.bats-packages.dev_bridge_<version>.bats
                          Path(repository) / name.split('/')[0] / name.split('/')[-1] / f'{flat}_{version}.bats',
                          Path(repository) / name.split('/')[-1] / f'{flat}_{version}.bats'):
            if candidate.exists():
                yield str(candidate)
                break
        else:
            print(f'# not in the repository: {name} {version}', file=sys.stderr)


VERDICTS = Path(__file__).with_name('proofs_audit_verdicts.txt')
SOLVER = Path(__file__).resolve().parent / 'solver'
KEY_FIELDS = 4


def key_of(label, proof, kind):
    """(scope, file, proof, kind) of a row: `quire` and the path from src/ on, or the package name
    (an archive `css_2026.9.28.58088.bats:src/harmony.bats` is css, src/harmony.bats)."""
    if ':' in label:
        archive, member = label.split(':', 1)
        return (re.sub(r'_\d[\d.]*(?:dev\d+)?\.bats$', '', archive), member, proof, kind)
    position = label.rfind('src/')
    return ('quire', label[position:] if position >= 0 else label, proof, kind)


def read_verdicts(path):
    """({key: (fixtures, reason)}, [problems]) of a verdicts file."""
    verdicts, problems = {}, []
    for number, text in enumerate(Path(path).read_text().split('\n'), 1):
        if not text.strip() or text.lstrip().startswith('#'):
            continue
        fields = [f.strip() for f in text.split('|')]
        if len(fields) != KEY_FIELDS + 2 or not all(fields[:KEY_FIELDS + 1]) or not fields[KEY_FIELDS + 1]:
            problems.append(f'{path}:{number}: not `scope | file | proof | kind | fixtures | reason`: {text[:80]}')
            continue
        key = tuple(fields[:KEY_FIELDS])
        if key in verdicts:
            problems.append(f'{path}:{number}: a second verdict for {" | ".join(key)}')
            continue
        evidence = [e.strip() for e in fields[KEY_FIELDS].split(',') if e.strip()]
        for item in evidence:
            if item.startswith('issue:'):
                if not item.startswith('issue:https://github.com/bats-lang/'):
                    problems.append(f'{path}:{number}: {item} is not an issue of bats-lang')
            else:
                for suffix in ('.dats', '.expect'):
                    if not (SOLVER / 'reject' / f'{item}{suffix}').exists():
                        problems.append(f'{path}:{number}: {item}{suffix} is not in tests/static/solver/reject/')
        verdicts[key] = (evidence, fields[KEY_FIELDS + 1], number)
    return verdicts, problems


def main(argv):
    fail_on, lock, repository, targets, summary, verdict_file, keys = None, None, None, [], False, None, False
    it = iter(argv)
    for a in it:
        if a == '--fail-on':
            fail_on = next(it).upper()
        elif a == '--summary':
            summary = True
        elif a == '--keys':
            keys = True
        elif a == '--lock':
            lock = next(it)
        elif a == '--repository':
            repository = next(it)
        elif a == '--verdicts':
            verdict_file = next(it)
        else:
            targets.append(a)
    if lock:
        targets += list(locked(lock, repository))
    results = []
    for label, text in sources(targets):
        results += audit(label, text)
    results.sort(key=lambda r: (-RANK[r[3]], r[0], r[1]))
    verdicts, problems = read_verdicts(verdict_file or VERDICTS)
    used = set()
    missing = []
    if keys:
        rows = {}
        for label, number, name, severity, kind, detail, line, proof in results:
            if severity == 'HIGH':
                rows.setdefault(key_of(label, proof, kind), []).append(number)
        for key, numbers in sorted(rows.items()):
            if key in verdicts:
                used.add(key)
                note = 'verdict: ' + ', '.join(verdicts[key][0])
            else:
                missing += [key]
                note = 'NO VERDICT'
            print(f'HIGH {" | ".join(key)}: {len(numbers)} rows at {",".join(map(str, sorted(set(numbers))))} => {note}')
    elif summary:
        groups = {}
        for label, number, name, severity, kind, detail, line, proof in results:
            g = groups.setdefault((label, name or '-', severity), {'lines': [], 'kinds': set()})
            g['lines'].append(number)
            g['kinds'].add(kind)
        for (label, name, severity), g in sorted(groups.items(), key=lambda kv: (-RANK[kv[0][2]], kv[0][0], kv[0][1])):
            lines = sorted(set(g['lines']))
            print(f'{severity:6} {label} {name}: {",".join(sorted(g["kinds"]))} at {",".join(map(str, lines[:6]))}{"..." if len(lines) > 6 else ""}')
    else:
        for label, number, name, severity, kind, detail, line, proof in results:
            note = ''
            if severity == 'HIGH':
                key = key_of(label, proof, kind)
                if key in verdicts:
                    used.add(key)
                    note = '   => verdict: ' + ', '.join(verdicts[key][0])
                else:
                    missing.append(key)
                    note = '   => NO VERDICT for ' + ' | '.join(key)
            print(f'{severity:6} {kind:13} {label}:{number} {proof}: {detail}   | {line[:100]}{note}')
    if summary:  # --summary counts the rows by key as --keys does
        for label, number, name, severity, kind, detail, line, proof in results:
            if severity == 'HIGH':
                key = key_of(label, proof, kind)
                if key in verdicts:
                    used.add(key)
                else:
                    missing.append(key)
    counts = {s: sum(1 for r in results if r[3] == s) for s in RANK}
    print(f'{counts["HIGH"]} high, {counts["MEDIUM"]} medium, {counts["LOW"]} low')
    for key in sorted(set(missing)):
        print(f'NO VERDICT: {" | ".join(key)}')
    for problem in problems:
        print(f'BAD VERDICT: {problem}')
    audited = {key_of(r[0], r[7], r[4])[0] for r in results}
    for key in sorted(k for k in set(verdicts) - used if k[0] in audited):
        print(f'# a verdict of no row now: {" | ".join(key)}')
    print(f'{len(set(used))} verdicts used, {len(set(missing))} rows without one, {len(problems)} bad verdicts')
    if fail_on:
        failing = [r for r in results if RANK[r[3]] >= RANK[fail_on] and not (r[3] == 'HIGH' and key_of(r[0], r[7], r[4]) in verdicts)]
        if failing or problems:
            return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
