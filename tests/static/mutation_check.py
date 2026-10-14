#!/usr/bin/env python3
"""Mutation check of the lemmas in a module (#594): a false variant of each
must be rejected by the compiler.

The 32-bit solver can make a proof's context contradictory (an overflow in
its elimination), and anything is then proved: a lemma can type-check and
prove nothing, with every other checker green. This is the probe Certora
and Frama-C describe as `assert false` (a rule that still passes with its
assertion replaced by false is vacuous), applied to each lemma: take its
statement, change it so that it is FALSE (one numeric index plus one, one
`==` of a guard shifted by one, a byte string consed with a byte), keep the
proof's body, and check that the compiler rejects it. A mutant that is
accepted is a lemma whose context is contradictory (vacuous), or one whose
mutation happens to be true: a person reads each (`ACCEPTED`) and decides.

For each lemma of the file (a `prfun` or `prfn` with a body; or a `#pub prfun`
with its `primplement`, whose body is used with the declared statement) a
private copy `_mutant_<n>_<name>` is inserted after it in the module, with
the original statement (a CONTROL, which must be accepted: it shows the copy
is a faithful one) and with each mutated statement. Private copies change no
`#pub` declaration, so only the module is checked again. Nothing is written
in the checkout: the work directory is a copy.

usage:
  tests/static/mutation_check.py --list <file.bats>...            the mutants, no compiler
  tests/static/mutation_check.py --run <work dir> <file.bats>...  <work dir> is a copy of the
      checkout, already checked (its build/ kept), `bats check` is run in it
      with env BATS_CHECK (default "bats check"); each <file.bats> is relative
      to it (src/bytes.bats).
  --only NAME   only the lemma NAME (repeatable)
  --report FILE write the results (one line a mutant) to FILE
  --known FILE  lemmas whose accepted mutants are explained (`file lemma reason`): an equivalent
                mutant, e.g. a lemma proved from FALSEP(), for which every statement is true
"""
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from proofs_audit import strip  # noqa: E402  (comments and strings blanked, lines kept)

ROOT = Path(__file__).resolve().parents[2]
KEYWORDS = ('prfun', 'prfn', 'primplement')
INT_SORTS = {'int', 'nat', 'pos', 'intGte', 'intGt'}
HEADER = re.compile(
    r'^(?P<path>\S+\.bats): \d+\(line=(?P<line>\d+), offs=\d+\) -- '
    r'\d+\(line=\d+, offs=\d+\): error\(\d+\): (?P<message>.*)$')


def balanced(text, start, opening, closing):
    """The index after the group that opens at text[start]."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == opening:
            depth += 1
        elif text[i] == closing:
            depth -= 1
            if depth == 0:
                return i + 1
    return len(text)


def depth0_equals(text, start):
    """The index of the first `=` of the definition at depth 0 from start, or -1."""
    depth = 0
    for i in range(start, len(text)):
        c = text[i]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == '=' and depth == 0:
            before = text[i - 1] if i else ' '
            after = text[i + 1] if i + 1 < len(text) else ' '
            if before in '=<>!/' or after in '=>/':
                continue
            return i
    return -1


def split_top(text, separator=','):
    parts, depth, last = [], 0, 0
    for i, c in enumerate(text):
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == separator and depth == 0:
            parts.append(text[last:i])
            last = i + 1
    parts.append(text[last:])
    return [p.strip() for p in parts]


class Decl:
    """One prfun, prfn or primplement chunk, taken apart."""

    def __init__(self, first, last, original, stripped):
        self.first, self.last = first, last  # 0-based line range [first, last)
        self.original, self.stripped = original, stripped
        self.ok = False
        text = stripped
        m = re.match(r'\s*(#pub\s+)?(prfun|prfn|primplement)\s+([A-Za-z_][\w\']*)', text)
        if not m:
            return
        self.pub, self.keyword, self.name = bool(m.group(1)), m.group(2), m.group(3)
        i = m.end()
        self.quantifiers, self.metric, self.args = [], '', None
        while True:
            while i < len(text) and text[i].isspace():
                i += 1
            if text.startswith('{', i):
                j = balanced(text, i, '{', '}')
                self.quantifiers.append(text[i:j])
                i = j
            elif text.startswith('.<', i):
                j = text.index('>.', i) + 2
                self.metric = text[i:j]
                i = j
            elif text.startswith('(', i) and self.args is None:
                j = balanced(text, i, '(', ')')
                self.args = text[i + 1:j - 1]
                i = j
            else:
                break
        self.result, self.body = None, None
        rest_from = i
        eq = depth0_equals(text, rest_from)
        head = text[rest_from:eq] if eq >= 0 else text[rest_from:]
        head = head.strip()
        if head.startswith(':'):
            self.result = head[1:].strip()
        if eq >= 0:
            # the body in the original text, same offsets
            self.body = original[eq + 1:].strip('\n')
        self.ok = self.args is not None

    def binders(self):
        names = []
        for group in self.quantifiers:
            inner = group[1:-1].split('|')[0]
            inner = inner.split(':')[0]
            names += [n.strip() for n in inner.split(',') if n.strip()]
        return names

    def sorts(self):
        """name -> sort for the quantified variables."""
        out = {}
        for group in self.quantifiers:
            inner = group[1:-1].split('|')[0]
            if ':' not in inner:
                continue
            names, sort = inner.split(':', 1)
            for n in names.split(','):
                out[n.strip()] = sort.strip()
        return out


def chunks_of(stripped_lines):
    start = None
    for index, line in enumerate(stripped_lines + ['']):
        if line.strip():
            if start is None:
                start = index
        elif start is not None:
            yield start, index
            start = None


def decls(original_lines, stripped_lines):
    found = []
    for first, last in chunks_of(stripped_lines):
        head = stripped_lines[first]
        if re.match(r'\s*(#pub\s+)?(prfun|prfn|primplement)\b', head):
            d = Decl(first, last, '\n'.join(original_lines[first:last]), '\n'.join(stripped_lines[first:last]))
            if d.ok:
                found.append(d)
    return found


# ---- mutation operators on a statement (a result type)

def int_like(arg, sorts):
    names = re.findall(r"[A-Za-z_][\w']*", arg)
    if not re.search(r'\d|[A-Za-z_]', arg):
        return False
    return all(sorts.get(n, '').split()[0:1] and sorts.get(n, '').split()[0] in INT_SORTS for n in names) and bool(names or re.search(r'\d', arg))


def bytes_like(arg, sorts):
    names = re.findall(r"[A-Za-z_][\w']*", arg)
    return bool(names) and all(sorts.get(n) == 'bytes' or n in ('bcons', 'bnil') for n in names)


def mutate(result, sorts):
    """(operator name, mutated statement) for each mutant of a statement."""
    out = []
    text = result
    # a guard or existential: [..] rest: each `==` has its right side shifted
    if text.startswith('['):
        close = balanced(text, 0, '[', ']')
        inside = text[1:close - 1]
        for m in re.finditer(r'(?<![=<>!])==(?!=)', inside):
            start = m.end()
            end = start
            depth = 0
            while end < len(inside):
                c = inside[end]
                if c in '([{':
                    depth += 1
                elif c in ')]}':
                    if depth == 0:
                        break
                    depth -= 1
                elif depth == 0 and (inside.startswith('&&', end) or inside.startswith('||', end) or c in '|;'):
                    break
                end += 1
            mutated = inside[:start] + ' (' + inside[start:end].strip() + ') + 1 ' + inside[end:]
            out.append((f'guard== #{len(out) + 1}', '[' + mutated + ']' + text[close:]))
    # the arguments of the statement's proposition: P(a, b, c)
    m = re.match(r"\s*([A-Za-z_][\w']*)\((.*)\)\s*$", text, re.S)
    if m:
        args = split_top(m.group(2))
        for index in range(len(args) - 1, -1, -1):
            arg = args[index]
            if int_like(arg, sorts):
                new = list(args)
                new[index] = f'({arg}) + 1'
                out.append((f'arg{index + 1}+1', f'{m.group(1)}({", ".join(new)})'))
            elif bytes_like(arg, sorts):
                new = list(args)
                new[index] = f'bcons(0, {arg})'
                out.append((f'arg{index + 1}:bcons', f'{m.group(1)}({", ".join(new)})'))
    return out


# ---- building the mutants of a file

class Mutant:
    def __init__(self, number, lemma, operator, statement, control):
        self.number, self.lemma, self.operator = number, lemma, operator
        self.statement, self.control = statement, control
        self.first = self.last = 0  # line range in the modified file (1-based, inclusive)
        self.status = ''
        self.message = ''

    @property
    def private_name(self):
        return f'_mutant_{self.number}_{self.lemma.name}'


class Lemma:
    def __init__(self, name, decl, impl, kind):
        self.name, self.decl, self.impl, self.kind = name, decl, impl, kind
        self.skipped = ''

    def parts(self):
        """(keyword, quantifiers, metric, args, result, body) of the statement."""
        d, i = self.decl, self.impl
        if self.kind == 'private':
            return d.keyword, ''.join(d.quantifiers), d.metric, d.args, d.result, d.body
        # a #pub declaration with its primplement: statement from the declaration,
        # argument names and body from the implementation
        decl_args, impl_args = split_top(d.args), split_top(i.args)
        if len(decl_args) != len(impl_args) or any('|' in a for a in decl_args):
            self.skipped = 'argument lists differ or hold a proof bar'
            return None
        if d.binders() != i.binders():
            self.skipped = 'binder names differ'
            return None
        args = ', '.join(f'{n}: {t}' for n, t in zip(impl_args, decl_args))
        if re.search(rf"(?<![\w']){re.escape(self.name)}(?![\w'])", i.body or ''):
            self.skipped = 'recursive primplement with no metric of its own'
            return None
        return 'prfn', ''.join(d.quantifiers), '', args, d.result, i.body


def lemmas_of(declarations):
    by_name = {}
    for d in declarations:
        by_name.setdefault((d.keyword == 'primplement', d.name), d)
    found = []
    for d in declarations:
        if d.keyword == 'primplement':
            declaration = by_name.get((False, d.name))
            if declaration is not None and declaration.result is not None and declaration.body is None:
                found.append(Lemma(d.name, declaration, d, 'public'))
        elif d.body is not None and d.result is not None:
            found.append(Lemma(d.name, d, None, 'private'))
    return found


def build(original_lines, only, with_mutants):
    """(lemmas with mutants, the controls-or-mutants block per insertion line)."""
    stripped = strip('\n'.join(original_lines)).split('\n')
    declarations = decls(original_lines, stripped)
    lemmas = [l for l in lemmas_of(declarations) if not only or l.name in only]
    mutants, number = [], 0
    for lemma in lemmas:
        parts = lemma.parts()
        if parts is None:
            continue
        keyword, quantifiers, metric, args, result, body = parts
        sorts = lemma.decl.sorts()
        number += 1
        mutants.append(Mutant(number, lemma, 'control', result, True))
        if with_mutants:
            for operator, statement in mutate(result, sorts):
                number += 1
                mutants.append(Mutant(number, lemma, operator, statement, False))
    return lemmas, mutants


def text_of(mutant):
    lemma = mutant.lemma
    keyword, quantifiers, metric, args, result, body = lemma.parts()
    new_body = re.sub(rf"(?<![\w']){re.escape(lemma.name)}(?![\w'])", mutant.private_name, body)
    label = 'control' if mutant.control else f'mutant {mutant.operator}'
    head = f'prfun {mutant.private_name} {quantifiers} {metric} ({args})\n  : {mutant.statement} ='
    head = re.sub(r'  +', ' ', head)
    if keyword == 'prfn' and not metric:
        head = head.replace('prfun ', 'prfn ', 1)
    return f'(* {label} of {lemma.name} *)\n{head}\n{new_body}\n'


def insert(original_lines, mutants):
    """The file's lines with each mutant after its lemma; sets the mutants' line ranges."""
    after = {}
    for m in mutants:
        end = (m.lemma.impl or m.lemma.decl).last
        after.setdefault(end, []).append(m)
    out, added = [], 0
    for index, line in enumerate(original_lines):
        if index in after:
            # a blank line separates the chunks
            pass
        out.append(line)
        if index + 1 in after:
            for m in after[index + 1]:
                block = text_of(m).split('\n')
                out.append('')
                start = len(out) + 1
                out += block
                m.first, m.last = start, len(out)
    return out


def errors(log):
    found, current = [], None
    for line in log.splitlines():
        h = HEADER.match(line)
        if h:
            current = (h['path'], int(h['line']), h['message'])
            found.append(current)
        elif line.strip() == '' or line.startswith(('typechecking', 'exit(', 'patsopt', 'error:')):
            current = None
    return found


def run_check(work, file, lines, mutants, check_command):
    (work / file).write_text('\n'.join(lines))
    done = subprocess.run(check_command, cwd=work, shell=True, capture_output=True, text=True)
    log = done.stdout + done.stderr
    return done.returncode, log, [e for e in errors(log) if e[0].endswith(file)]


def classify(mutants, errs):
    resolved = 0
    for m in mutants:
        mine = [e for e in errs if m.first <= e[1] <= m.last]
        if mine:
            m.message = mine[0][2]
            broken = re.search(r'syntax|unrecogni[sz]ed|unbound|not defined|parsing', m.message, re.I)
            m.status = 'BROKEN' if broken else ('CONTROL-FAILED' if m.control else 'REJECTED')
            resolved += 1
    return resolved


def main(argv):
    only, report, mode, work, files, known_file = set(), None, None, None, [], None
    it = iter(argv)
    for a in it:
        if a == '--list':
            mode = 'list'
        elif a == '--run':
            mode, work = 'run', Path(next(it))
        elif a == '--only':
            only.add(next(it))
        elif a == '--report':
            report = next(it)
        elif a == '--known':
            known_file = next(it)
        else:
            files.append(a)
    if mode is None or not files:
        print(__doc__)
        return 2
    known = {}
    if known_file:
        for entry in Path(known_file).read_text().splitlines():
            if entry.strip() and not entry.startswith('#'):
                file_, lemma_, reason = entry.split(None, 2)
                known[(file_, lemma_)] = reason
    check_command = os.environ.get('BATS_CHECK', 'bats check')
    lines_out, accepted = [], 0
    for file in files:
        # the pristine text is the checkout's, not a previous run's
        original = (ROOT / file).read_text() if (ROOT / file).exists() else Path(file).read_text()
        original_lines = original.split('\n')
        lemmas, mutants = build(original_lines, only, True)
        for lemma in lemmas:
            if lemma.parts() is None:
                lines_out.append(f'SKIPPED  {file} {lemma.name}: {lemma.skipped}')
        for lemma in lemmas:
            if not any(m.lemma is lemma and not m.control for m in mutants) and lemma.parts() is not None:
                lines_out.append(f'NOMUTANT {file} {lemma.name}: no operator applies to {lemma.parts()[4]!r}')
        if mode == 'list':
            for m in mutants:
                lines_out.append(f'{"control" if m.control else "mutant ":7} {file} {m.lemma.name} {m.operator}: {m.statement}')
            continue
        controls = [m for m in mutants if m.control]
        try:
            lines = insert(original_lines, controls)
            code, log, errs = run_check(work, file, lines, controls, check_command)
            classify(controls, errs)
            usable = {m.lemma for m in controls if m.status == ''}
            for m in controls:
                if m.status:
                    lines_out.append(f'HARNESS  {file} {m.lemma.name}: control {m.status}: {m.message}')
            pending = [m for m in mutants if not m.control and m.lemma in usable]
            while pending:
                lines = insert(original_lines, pending)
                code, log, errs = run_check(work, file, lines, pending, check_command)
                for m in pending:
                    m.status = ''
                got = classify(pending, errs)
                if not got:
                    for m in pending:
                        reason = known.get((file, m.lemma.name))
                        m.status = 'KNOWN' if reason else 'ACCEPTED'
                        lines_out.append(f'{m.status:9} {file} {m.lemma.name} {m.operator}: {m.statement}' + (f'  ({reason})' if reason else ''))
                        accepted += 0 if reason else 1
                    break
                for m in [m for m in pending if m.status]:
                    lines_out.append(f'{m.status:9} {file} {m.lemma.name} {m.operator}: {m.message[:90]}')
                pending = [m for m in pending if not m.status]
        finally:
            (work / file).write_text(original)
    for line in lines_out:
        print(line)
    if report:
        Path(report).write_text('\n'.join(lines_out) + '\n')
    if mode == 'run':
        print(f'{accepted} mutant(s) accepted')
    return 1 if accepted else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
