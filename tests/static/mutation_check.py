#!/usr/bin/env python3
"""Mutation check of the lemmas in a module (#594): a false variant of each
must be rejected by the compiler.

The solver can make a proof's context contradictory (the -int build's
overflow, or a hypothesis that two matched copies of one constructor make
unsatisfiable), and anything is then proved: a lemma can type-check and
prove nothing, with every other checker green. This is the probe Certora
and Frama-C describe as `assert false` (a rule that still passes with its
assertion replaced by false is vacuous), applied to each lemma: take its
statement, change it so that it is FALSE, keep the proof's body, and check
that the compiler rejects it. A mutant that is accepted is a lemma whose
context is contradictory (vacuous), or one whose mutation happens to be
true: a person reads each (`ACCEPTED`) and decides, and an equivalent
mutant is explained in a --known file.

The operators (`mutate`), on the statement of a lemma, its result type:
  probe 1==2       `[guard] void` becomes `[1 == 2] void`: the cheap vacuity probe
  guard==          a `==` of a guard `[..]` has its right side plus one
  bound+1          a guard `a < b` or `a <= b` becomes `a + 1 < b`
  bound>= / bound<=  a guard's bound on a constant is tightened by one
  arg<i>+1         the i-th argument of the proposition, an int, plus one
  arg<i>:bcons     the i-th argument, a byte string, consed with a byte
  arg<i>:fresh     the i-th argument, a variable of another sort, replaced
                   by a fresh universally quantified one (`P(a, fresh)`)
  part<i> ...      the same, in the i-th proposition of a tuple result
Existential prefixes `[a: int | guard]` are walked one group at a time and
their binders are known sorts for the arguments after them.

For each lemma of the file (a `prfun` or `prfn` with a body; or a `#pub
prfun` with its `primplement`, whose body is used with the declared
statement) a private copy `_mutant_<n>_<name>` is inserted after it in the
module, with the original statement (a CONTROL, which must be accepted: it
shows the copy is a faithful one) and with each mutated statement. Private
copies change no `#pub` declaration, so only the module is checked again.
A recursive `#pub` lemma cannot be copied (it calls itself by its name):
with --inplace its declaration and primplement are changed where they
stand, which checks the module's dependents again, one mutant a run.
Nothing is written in the checkout: the work directory is a copy.

usage:
  tests/static/mutation_check.py --list <file.bats>...            the mutants, no compiler
  tests/static/mutation_check.py --run <work dir> <file.bats>...  <work dir> is a copy of the
      checkout, already checked (its build/ kept), `bats check` is run in it
      with env BATS_CHECK (default "bats check"); each <file.bats> is relative
      to it (src/bytes.bats).
  --root DIR    the pristine package the files are read from (default: this checkout); <work dir> is a
                copy of it (a package of another repository: css, arith, sha256 ...)
  --inplace     also the recursive #pub lemmas
  --only NAME   only the lemma NAME (repeatable)
  --diff BASE   only the lemmas the changes since the git revision BASE can have made vacuous
                (`select_by_diff`): those the diff touches, those that mention a name it declares
  --shard I/N   only the I-th of N parts of the lemmas otherwise selected (1 <= I <= N), balanced by
                their number of mutants, heaviest first to the lightest part (`partition`): the parts
                are disjoint and together are every lemma, the same for the same file, so N jobs
                side by side run the module in about 1/N of the time plus the app's check
  --member NAME the module and part a static member names (mutation/crc-part2of5, from
                tests/static/mutation_modules.txt): --file and --shard in one word
  --report FILE write the results (one line a mutant) to FILE
  --ats-home DIR  run the compiler with DIR as its ATS home (~/.bats/ats2): another patsopt
                (the infinite-precision solver) with the same checks
  --known FILE  accepted mutants that are explained (`file | lemma | operator | reason`, operator
                `*` for all of the lemma's): an equivalent mutant, e.g. a lemma proved from FALSEP(),
                for which every statement is true. Any other accepted mutant fails the check
"""
import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from proofs_audit import strip  # noqa: E402  (comments and strings blanked, lines kept)

INT_SORTS = {'int', 'nat', 'pos', 'intGte', 'intGt'}
FRESH_NAME = 'mutant_fresh'
IDENTIFIER = r"[A-Za-z_][\w']*"
HEADER = re.compile(
    r'^(?P<path>\S+\.bats): \d+\(line=(?P<line>\d+), offs=\d+\) -- '
    r'\d+\(line=\d+, offs=\d+\): error\((?:\d+|parsing|lexing)\): (?P<message>.*)$')
BATS_ERROR = re.compile(r'^\s*--> (?P<path>\S+):(?P<line>\d+):\d+')
# What, in a diff, can have changed the meaning of every proof: the solver (the ATS2 pin and the
# solver's own fixtures). The ATS2 build is installed by bats's setup action (bats#280), called by
# commit from the workflows, so a changed line there that names the action is a move of that pin.
# A compiler or package move is the scheduled run's.
EVERYTHING_PATHS = ('tests/static/solver.py',)
SETUP_ACTION = 'bats-lang/bats/.github/actions/setup@'
SETUP_ACTION_WORKFLOWS = ('.github/workflows/check.yml', '.github/workflows/mutation.yml', '.github/workflows/deploy.yml')
EVERYTHING_PREFIXES = ('tests/static/solver/',)
# A change to the checker and its data selects a smoke set (the modules marked `smoke` in
# mutation_modules.txt), not every lemma: it is the scheduled run's to run the new checker on all
CHECKER_PATHS = (
    'tests/static/mutation_check.py', 'tests/static/mutation_test.py', 'tests/static/mutation_modules.txt',
    'tests/static/mutation_known.txt', 'tests/static/proofs_audit.py')
MODULES_FILE = 'tests/static/mutation_modules.txt'


def read_modules(root):
    """[(file, shards, smoke)] from tests/static/mutation_modules.txt: `src/crc.bats 5 smoke`."""
    path = Path(root) / MODULES_FILE
    out = []
    if path.exists():
        for line in path.read_text().splitlines():
            fields = line.split()
            if fields and not fields[0].startswith('#'):
                out.append((fields[0], int(fields[1]) if len(fields) > 1 else 1, 'smoke' in fields[2:]))
    return out


def member_name(file, shards, index):
    """The static member (tests/groups.json) of a module's shard: mutation/crc-part2of5."""
    base = Path(file).stem
    return f'mutation/{base}' if shards == 1 else f'mutation/{base}-part{index}of{shards}'


def parse_member(root, member):
    """(file, index, count) of a member name `mutation/crc` or `mutation/crc-part2of5`."""
    for file, shards, _ in read_modules(root):
        for index in range(1, shards + 1):
            if member_name(file, shards, index) == member:
                return file, index, shards
    raise KeyError(member)


def partition(weights, count):
    """Splits [(name, weight)] into `count` sets of names, balanced by weight: heaviest first, each
    to the lightest set so far (the lowest number on a tie). Deterministic: the sets partition the
    names, whatever the order they come in."""
    sets, totals = [set() for _ in range(count)], [0] * count
    for name, weight in sorted(weights, key=lambda item: (-item[1], item[0])):
        lightest = totals.index(min(totals))
        sets[lightest].add(name)
        totals[lightest] += weight
    return sets


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
        m = re.match(rf'\s*(#pub\s+)?(prfun|prfn|primplement)\s+({IDENTIFIER})', text)
        if not m:
            return
        self.pub, self.keyword, self.name = bool(m.group(1)), m.group(2), m.group(3)
        i = m.end()
        self.quantifier_end = i  # where one more quantifier can be written
        self.quantifiers, self.metric, self.args = [], '', None
        while True:
            while i < len(text) and text[i].isspace():
                i += 1
            if text.startswith('{', i):
                j = balanced(text, i, '{', '}')
                self.quantifiers.append(text[i:j])
                i = self.quantifier_end = j
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
        eq = depth0_equals(text, i)
        head = (text[i:eq] if eq >= 0 else text[i:]).strip()
        if head.startswith(':'):
            self.result = head[1:].strip()
        if eq >= 0:
            # the body in the original text, same offsets
            self.body = original[eq + 1:].strip('\n')
        self.ok = self.args is not None

    def binders(self):
        names = []
        for group in self.quantifiers:
            inner = group[1:-1].split('|')[0].split(':')[0]
            names += [n.strip() for n in inner.split(',') if n.strip()]
        return names

    def sorts(self):
        """name -> sort for the quantified variables."""
        out = {}
        for group in self.quantifiers:
            out.update(binder_sorts(group[1:-1]))
        return out


def binder_sorts(inside):
    """name -> sort of the binders in `a, b: int, c: bytes | guard` (a guard has none)."""
    sorts, pending = {}, []
    for part in split_top(inside.split('|')[0]):
        name, colon, sort = part.partition(':')
        pending.append(name.strip())
        if colon:
            sorts.update({n: sort.strip() for n in pending})
            pending = []
    return sorts


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
        if re.match(r'\s*(#pub\s+)?(prfun|prfn|primplement)\b', stripped_lines[first]):
            d = Decl(first, last, '\n'.join(original_lines[first:last]), '\n'.join(stripped_lines[first:last]))
            if d.ok:
                found.append(d)
    return found


# ---- mutation operators on a statement (a result type)

class Variant:
    """A mutated statement; `extra` is a quantifier it adds (a fresh variable)."""

    def __init__(self, operator, statement, extra=''):
        self.operator, self.statement, self.extra = operator, statement, extra


def sort_name(sort):
    return sort.split()[0] if sort.split() else ''


def int_like(arg, sorts):
    names = re.findall(IDENTIFIER, arg)
    return all(sort_name(sorts.get(n, '')) in INT_SORTS for n in names) and bool(names or re.search(r'\d', arg))


def bytes_like(arg, sorts):
    names = re.findall(IDENTIFIER, arg)
    return bool(names) and all(sorts.get(n) == 'bytes' or n in ('bcons', 'bnil') for n in names)


def guard_variants(inside):
    """(operator, new text of the guard) for each way to make a guard false."""
    out = []
    for m in re.finditer(r'(?<![=<>!])==(?!=)', inside):
        start, end, depth = m.end(), m.end(), 0
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
        out.append(('guard==', inside[:start] + ' (' + inside[start:end].strip() + ') + 1 ' + inside[end:]))
    for m in re.finditer(r'(?<![=<>!-])(<=|<)(?![=<>])', inside):
        # a bound A < B: the mutant A + 1 < B is false where A can reach B - 1
        lhs = re.split(r';|&&|\|', inside[:m.start()])[-1].strip()
        if lhs and re.fullmatch(r"[\w' +*-]+", lhs):
            at = inside[:m.start()].rfind(lhs)
            out.append(('bound+1', inside[:at] + f'({lhs}) + 1 ' + inside[at + len(lhs):]))
    for m in re.finditer(r'(>=|<=)\s*(\d+)', inside):
        n = int(m.group(2))
        tighter = n + 1 if m.group(1) == '>=' else n - 1
        if tighter >= 0:
            out.append((f'bound{m.group(1)}', inside[:m.start(2)] + str(tighter) + inside[m.end(2):]))
    return out


def prop_variants(prop, sorts):
    """(operator, mutated proposition, extra quantifier) for `Name(args)`."""
    m = re.match(rf"\s*([$A-Za-z_][\w'.$]*)\((.*)\)\s*$", prop, re.S)
    if not m:
        return []
    args, out = split_top(m.group(2)), []
    for index in range(len(args) - 1, -1, -1):
        arg = args[index]
        replacements = []
        if int_like(arg, sorts):
            replacements.append((f'arg{index + 1}+1', f'({arg}) + 1', ''))
        elif bytes_like(arg, sorts):
            replacements.append((f'arg{index + 1}:bcons', f'bcons(0, {arg})', ''))
        elif re.fullmatch(IDENTIFIER, arg) and sorts.get(arg):
            replacements.append((f'arg{index + 1}:fresh', FRESH_NAME, '{%s: %s}' % (FRESH_NAME, sorts[arg])))
        for operator, replacement, extra in replacements:
            new = list(args)
            new[index] = replacement
            out.append((operator, f'{m.group(1)}({", ".join(new)})', extra))
    return out


def mutate(result, sorts):
    """The Variants of a statement."""
    sorts = dict(sorts)
    out = []
    if re.fullmatch(r'\[[^\]]*\]\s*void', result):
        out.append(Variant('probe 1==2', '[1 == 2] void'))
    # existential prefixes and guards, one group at a time: [a: int | guard] [guard] ...
    prefix, rest = '', result.strip()
    while rest.startswith('['):
        cut = balanced(rest, 0, '[', ']')
        group, rest = rest[:cut], rest[cut:].lstrip()
        inside = group[1:-1]
        binders = binder_sorts(inside) if ('|' in inside or (':' in inside and not re.search(r'[<>=]', inside))) else {}
        sorts.update(binders)
        guard = inside.partition('|')[2] if '|' in inside else ('' if binders else inside)
        if guard.strip():
            head = '[' + inside[:len(inside) - len(guard)]
            for operator, changed in guard_variants(guard):
                out.append(Variant(operator, prefix + head + changed + ']' + (' ' + rest if rest else '')))
        prefix += group + ' '
    # the proposition: P(args), or a tuple of them
    whole = rest.strip()
    if whole.startswith('(') and balanced(whole, 0, '(', ')') == len(whole):
        parts = split_top(whole[1:-1])
        if len(parts) > 1:
            for number, part in enumerate(parts, 1):
                for operator, changed, extra in prop_variants(part, sorts):
                    new = list(parts)
                    new[number - 1] = changed
                    out.append(Variant(f'part{number} {operator}', f'{prefix}({", ".join(new)})', extra))
            return dedupe(out)
    for operator, changed, extra in prop_variants(whole, sorts):
        out.append(Variant(operator, prefix + changed, extra))
    return dedupe(out)


def dedupe(variants):
    seen, out = set(), []
    for v in variants:
        key = (v.statement, v.extra)
        if key not in seen:
            seen.add(key)
            out.append(v)
    return out


# ---- building the mutants of a file

class Mutant:
    def __init__(self, number, lemma, variant, control):
        self.number, self.lemma, self.control = number, lemma, control
        self.operator = 'control' if control else variant.operator
        self.statement = lemma.parts()[4] if control else variant.statement
        self.extra = '' if control else variant.extra
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
        self.inplace = False

    @property
    def first(self):
        return min(self.decl.first, self.impl.first) if self.impl else self.decl.first

    @property
    def last(self):
        return max(self.decl.last, self.impl.last) if self.impl else self.decl.last

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
        # a declaration may name its arguments (`cells_set: SETC(..)`): the implementation's name is kept
        args = ', '.join(f'{n}: {re.sub(r"^\w+\s*:\s*", "", t.strip())}'
                         for n, t in zip(impl_args, decl_args)) if any(decl_args) else ''
        if re.search(rf"(?<![\w']){re.escape(self.name)}(?![\w'])", i.body or ''):
            self.inplace = True
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


def build(original_lines, only, wanted=None):
    """(lemmas, mutants): a control and the mutants of each lemma named in `only`
    (all when empty) and in `wanted` (a set of names, or None for all)."""
    stripped = strip('\n'.join(original_lines)).split('\n')
    lemmas = [l for l in lemmas_of(decls(original_lines, stripped))
              if (not only or l.name in only) and (wanted is None or l.name in wanted)]
    mutants, number = [], 0
    for lemma in lemmas:
        if lemma.parts() is None:
            continue
        number += 1
        mutants.append(Mutant(number, lemma, None, True))
        for variant in mutate(lemma.parts()[4], lemma.decl.sorts()):
            number += 1
            mutants.append(Mutant(number, lemma, variant, False))
    return lemmas, mutants


def text_of(mutant):
    lemma = mutant.lemma
    keyword, quantifiers, metric, args, result, body = lemma.parts()
    new_body = re.sub(rf"(?<![\w']){re.escape(lemma.name)}(?![\w'])", mutant.private_name, body)
    label = 'control' if mutant.control else f'mutant {mutant.operator}'
    head = f'prfun {mutant.private_name} {quantifiers}{mutant.extra} {metric} ({args})\n  : {mutant.statement} ='
    head = re.sub(r'  +', ' ', head)
    if keyword == 'prfn' and not metric:
        head = head.replace('prfun ', 'prfn ', 1)
    return f'(* {label} of {lemma.name} *)\n{head}\n{new_body}\n'


def insert(original_lines, mutants):
    """The file's lines with each mutant after its lemma; sets the mutants' line ranges."""
    after = {}
    for m in mutants:
        after.setdefault((m.lemma.impl or m.lemma.decl).last, []).append(m)
    out = []
    for index, line in enumerate(original_lines):
        out.append(line)
        for m in after.get(index + 1, []):
            block = text_of(m).split('\n')
            out.append('')
            start = len(out) + 1
            out += block
            m.first, m.last = start, len(out)
    return out


def inplace_edit(original_lines, lemma, mutant):
    """(the file's lines with the statement changed where the lemma is declared and
    implemented, the 1-based line range of both)."""
    def changed(declaration, with_result):
        text = '\n'.join(original_lines[declaration.first:declaration.last])
        if with_result:
            at = text.rfind(declaration.result)
            text = text[:at] + mutant.statement + text[at + len(declaration.result):]
        if mutant.extra:
            at = declaration.quantifier_end
            text = text[:at] + ' ' + mutant.extra + text[at:]
        return text.split('\n')
    decl, impl = lemma.decl, lemma.impl
    new_decl, new_impl = changed(decl, True), changed(impl, False)
    lines = (original_lines[:decl.first] + new_decl + original_lines[decl.last:impl.first]
             + new_impl + original_lines[impl.last:])
    end = impl.first + (len(new_decl) - (decl.last - decl.first)) + len(new_impl)
    return lines, (decl.first + 1, end)


# ---- which lemmas a diff can have made vacuous

DECLARED = re.compile(
    rf"\b(?:prfun|prfn|primplement|dataprop|dataview|datasort|stadef|absprop|propdef|prval)\s+(?:\{{[^}}]*\}}\s*)*({IDENTIFIER})"
    rf"|^\s*\|\s*(?:\{{[^}}]*\}}\s*)*({IDENTIFIER})\b", re.M)


def changed_lines(root, base, file):
    """(new line numbers 1-based, the changed text) of FILE since BASE: added or changed lines."""
    done = subprocess.run(['git', '-C', str(root), 'diff', '-U0', '--no-color', base, '--', file],
                          capture_output=True, text=True, check=True)
    numbers, text, current = set(), [], 0
    for line in done.stdout.splitlines():
        h = re.match(r'@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@', line)
        if h:
            current = int(h.group(1))
        elif current and line.startswith('+') and not line.startswith('+++'):
            numbers.add(current)
            text.append(line[1:])
            current += 1
        elif line.startswith('-') and not line.startswith('---'):
            text.append(line[1:])
    return numbers, '\n'.join(text)


def changed_files(root, base):
    done = subprocess.run(['git', '-C', str(root), 'diff', '--name-only', base], capture_output=True, text=True, check=True)
    return done.stdout.split()


def select_by_diff(root, base, file):
    """The lemma names of FILE the changes since BASE can have made vacuous, or None for all.

    A lemma is selected when the diff touches it (cargo-mutants' --in-diff, Stryker's
    incremental mode: what is unchanged keeps its earlier result), or when it mentions a name
    a changed line declares (a lemma it calls whose statement changed, a dataprop it uses), or
    when the diff touches the file outside any lemma (a dataprop, a helper: every lemma of
    the file may depend on it). A diff of the solver (its pin or fixtures) selects everything; a
    diff of the checker alone selects the smoke modules whole and nothing else."""
    changed = changed_files(root, base)
    if any(path in EVERYTHING_PATHS or path.startswith(EVERYTHING_PREFIXES) for path in changed):
        return None
    if any(SETUP_ACTION in changed_lines(root, base, path)[1] for path in changed if path in SETUP_ACTION_WORKFLOWS):
        return None
    if any(path in CHECKER_PATHS for path in changed) and any(m == file and smoke for m, _, smoke in read_modules(root)):
        return None
    modules = [path for path in changed if path.endswith('.bats')]
    names = set()
    for path in modules:
        _, text = changed_lines(root, base, path)
        names |= {a or b for a, b in DECLARED.findall(text)}
    original = (Path(root) / file).read_text()
    lines = original.split('\n')
    stripped = strip(original).split('\n')
    lemmas = lemmas_of(decls(lines, stripped))
    selected = set()
    if file in modules:
        numbers, _ = changed_lines(root, base, file)
        for number in numbers:
            if not stripped[number - 1].strip():
                continue  # a comment or a blank
            inside = [l for l in lemmas if l.first < number <= l.last]
            if inside:
                selected |= {l.name for l in inside}
                names |= {l.name for l in inside}
            else:
                return None
    if names:
        for lemma in lemmas:
            text = '\n'.join(stripped[lemma.first:lemma.last])
            if any(re.search(rf"(?<![\w']){re.escape(n)}(?![\w'])", text) for n in names):
                selected.add(lemma.name)
    return selected


def selected_names(root, file, original_lines, only, base, shard):
    """The names of the lemmas to mutate: those of `--only`, those the diff since `base` selects,
    and of those the shard (index, count) the caller is."""
    lemmas, mutants = build(original_lines, only)
    weights = {}
    for m in mutants:
        weights[m.lemma.name] = weights.get(m.lemma.name, 0) + 1
    names = [l.name for l in lemmas if l.parts() is not None]
    if base:
        wanted = select_by_diff(root, base, file)
        if wanted is not None:
            names = [n for n in names if n in wanted]
    if shard:
        index, count = shard
        names = partition([(n, weights.get(n, 1)) for n in names], count)[index - 1]
    return set(names)


# ---- running the compiler

def errors(log):
    found = []
    lines = log.splitlines()
    for index, line in enumerate(lines):
        # bats's own errors (before patsopt): "error: <message>" then " --> file:line:col"
        b = BATS_ERROR.match(line)
        if b and index and lines[index - 1].startswith('error:'):
            found.append((b['path'], int(b['line']), lines[index - 1]))
        elif b and index > 1 and lines[index - 2].startswith('error:'):
            found.append((b['path'], int(b['line']), lines[index - 2]))
        else:
            h = HEADER.match(line)
            if h:
                found.append((h['path'], int(h['line']), h['message']))
    return found


def run_check(work, file, lines, check_command):
    (work / file).write_text('\n'.join(lines))
    done = subprocess.run(check_command, cwd=work, shell=True, capture_output=True, text=True)
    log = done.stdout + done.stderr
    if os.environ.get('MUTATION_LOGS'):
        directory = Path(os.environ['MUTATION_LOGS'])
        directory.mkdir(parents=True, exist_ok=True)
        (directory / f'{len(list(directory.glob("*.log"))):03d}-{Path(file).name}.log').write_text(f'rc={done.returncode}\n' + log)
    return done.returncode, log, [e for e in errors(log) if e[0].endswith(file)]


def classify(mutants, errs):
    for m in mutants:
        mine = [e for e in errs if m.first <= e[1] <= m.last]
        if mine:
            m.message = mine[0][2]
            broken = re.search(r'syntax|unrecogni[sz]ed|unbound|not defined|parsing', m.message, re.I)
            m.status = 'BROKEN' if broken else ('CONTROL-FAILED' if m.control else 'REJECTED')


class Report:
    def __init__(self, known):
        self.known, self.lines = known, []
        self.accepted = self.broken = self.harness = self.rejected = 0

    def add(self, line):
        self.lines.append(line)

    def accepted_mutant(self, file, m):
        reason = self.known.get((file, m.lemma.name, m.operator)) or self.known.get((file, m.lemma.name, '*'))
        m.status = 'KNOWN' if reason else 'ACCEPTED'
        self.accepted += 0 if reason else 1
        self.add(f'{m.status:9} {file} {m.lemma.name} {m.operator}: {m.statement}' + (f'  ({reason})' if reason else ''))

    def mutant(self, file, m, suffix=''):
        if m.status == 'REJECTED':
            self.rejected += 1
        elif m.status == 'BROKEN':
            self.broken += 1
        self.add(f'{m.status:9} {file} {m.lemma.name} {m.operator}{suffix}: {m.message[:90]}')


def check_file(file, original_lines, lemmas, mutants, work, check_command, do_inplace, report):
    for lemma in lemmas:
        if lemma.parts() is None:
            report.add(f'SKIPPED  {file} {lemma.name}: {lemma.skipped}')
        elif not any(m.lemma is lemma and not m.control for m in mutants):
            report.add(f'NOMUTANT {file} {lemma.name}: no operator applies to {lemma.parts()[4]!r}')
    inplace = [m for m in mutants if m.lemma.inplace and not m.control]
    mutants = [m for m in mutants if not m.lemma.inplace]
    if inplace and not do_inplace:
        for name in sorted({m.lemma.name for m in inplace}):
            report.add(f'SKIPPED  {file} {name}: recursive (--inplace checks the module\'s dependents again for each of its mutants)')
        inplace = []
    controls = [m for m in mutants if m.control]
    code, log, errs = run_check(work, file, insert(original_lines, controls), check_command)
    classify(controls, errs)
    if code != 0 and not any(m.status for m in controls):
        # the module with only its controls does not check, for a reason outside them
        report.harness += 1
        report.add(f'HARNESS  {file}: the check fails with the controls only: ' + (log.strip().splitlines() or ['no output'])[-1][:160])
        return
    usable = {m.lemma for m in controls if not m.status}
    for m in controls:
        if m.status:
            report.harness += 1
            report.add(f'HARNESS  {file} {m.lemma.name}: control {m.status}: {m.message}')
    for m in inplace:
        lines, (first, last) = inplace_edit(original_lines, m.lemma, m)
        code, _, errs = run_check(work, file, lines, check_command)
        inside = [e for e in errs if first <= e[1] <= last]
        if inside:
            m.status, m.message = 'REJECTED', inside[0][2]
        elif code == 0:
            report.accepted_mutant(file, m)
            continue
        else:
            m.status, m.message = 'BROKEN', (errs[0][2] if errs else 'check failed')
        report.mutant(file, m, ' (in place)')
    pending = [m for m in mutants if not m.control and m.lemma in usable]
    while pending:
        code, log, errs = run_check(work, file, insert(original_lines, pending), check_command)
        for m in pending:
            m.status = ''
        classify(pending, errs)
        resolved = [m for m in pending if m.status]
        if not resolved and code != 0:
            first = errs[0] if errs else None
            report.broken += len(pending)
            for m in pending:
                report.add(f'BROKEN    {file} {m.lemma.name} {m.operator}: check failed outside the mutants: '
                           + (f'{first[1]}: {first[2][:80]}' if first else (log.strip().splitlines() or ['no output'])[-1][:100]))
            return
        if not resolved:
            for m in pending:
                report.accepted_mutant(file, m)
            return
        for m in resolved:
            report.mutant(file, m)
        # patsopt may stop at its first error in a module: the rest go again
        pending = [m for m in pending if not m.status]


def read_known(path):
    """`file | lemma | operator | reason` lines (operator `*`: every mutant of the lemma)."""
    known = {}
    if path:
        for entry in Path(path).read_text().splitlines():
            if entry.strip() and not entry.startswith('#'):
                file, lemma, operator, reason = [part.strip() for part in entry.split('|', 3)]
                known[(file, lemma, operator)] = reason
    return known


def use_ats_home(ats_home):
    """A HOME whose ~/.bats is the real one except ats2, which is ats_home: the
    compiler finds patsopt there (a solver build chosen per run, #594)."""
    fake = Path(os.environ.get('TMPDIR', '/tmp')) / f'mutation-home-{os.getpid()}'
    (fake / '.bats').mkdir(parents=True, exist_ok=True)
    real = Path(os.environ.get('HOME', '/root')) / '.bats'
    for entry in real.iterdir():
        if entry.name != 'ats2' and not (fake / '.bats' / entry.name).exists():
            (fake / '.bats' / entry.name).symlink_to(entry)
    if not (fake / '.bats' / 'ats2').exists():
        (fake / '.bats' / 'ats2').symlink_to(Path(ats_home).resolve())
    os.environ['HOME'] = str(fake)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split('usage:')[0], add_help=True)
    parser.add_argument('--list', action='store_true')
    parser.add_argument('--run', metavar='WORK')
    parser.add_argument('--root', default=str(Path(__file__).resolve().parents[2]))
    parser.add_argument('--inplace', action='store_true')
    parser.add_argument('--only', action='append', default=[])
    parser.add_argument('--diff', metavar='BASE')
    parser.add_argument('--shard', metavar='I/N')
    parser.add_argument('--member', metavar='NAME')
    parser.add_argument('--report')
    parser.add_argument('--ats-home')
    parser.add_argument('--known')
    parser.add_argument('files', nargs='*')
    args = parser.parse_args(argv)
    root, known = Path(args.root).resolve(), read_known(args.known)
    shard = tuple(int(n) for n in args.shard.split('/')) if args.shard else None
    if args.member:
        file, index, count = parse_member(root, args.member)
        args.files, shard = [file], (index, count)
    if bool(args.list) == bool(args.run) or not args.files:
        print(__doc__)
        return 2
    if args.ats_home:
        use_ats_home(args.ats_home)
    check_command = os.environ.get('BATS_CHECK', 'bats check')
    report = Report(known)
    work = Path(args.run).resolve() if args.run else None
    for file in args.files:
        # the pristine text is the checkout's, not a previous run's
        original = (root / file).read_text() if (root / file).exists() else Path(file).read_text()
        original_lines = original.split('\n')
        wanted = selected_names(root, file, original_lines, set(args.only), args.diff, shard)
        if not wanted:
            report.add(f'UNCHANGED {file}: no lemma to mutate (the diff touches none, or the shard has none)')
            continue
        lemmas, mutants = build(original_lines, set(args.only), wanted)
        if args.list:
            for lemma in lemmas:
                if lemma.parts() is None:
                    report.add(f'SKIPPED  {file} {lemma.name}: {lemma.skipped}')
            for m in mutants:
                report.add(f'{"control" if m.control else "mutant ":7} {file} {m.lemma.name} {m.operator}: {m.statement}'
                           + (f' with {m.extra}' if m.extra else ''))
            continue
        try:
            check_file(file, original_lines, lemmas, mutants, work, check_command, args.inplace, report)
        finally:
            (work / file).write_text(original)
    print('\n'.join(report.lines))
    if args.report:
        Path(args.report).write_text('\n'.join(report.lines) + '\n')
    if args.run:
        print(f'{report.rejected} mutant(s) rejected, {report.accepted} accepted, {report.broken} broken, '
              f'{report.harness} controls failed')
    return 1 if (report.accepted or report.broken or report.harness) else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
