#!/usr/bin/env python3
"""Which e2e specs and static members a change can affect (quire#619).

A pull request's check ran every group whatever it changed: a CLAUDE.md edit
cost the e2e suite and the static fixtures. This module decides, from the
paths a change touched, which of them can have a different result, and fails
closed: a path no rule names selects everything.

The decision is made once, in the `plan` job (`scripts/ci-groups.py plan`),
and each group job reads it; a group (or a static member) that is not
selected ends after its first step with success, so the required `check`
needs no exception. The rules are the table RULES below, first match wins,
each saying what the path selects of the e2e specs and of the static
members. A selected set is a set of names, or ALL.

* e2e: a spec is selected by a change to itself or to anything it reaches
  through `import`, `import()` or `require` (the books, the helpers); a file
  that is no module (a font, a JSON, an mp3) selects the specs reaching a
  module that names it (or its directory); a module no spec reaches, or a
  deletion, selects every spec. A group is selected when one of its specs is.
* static: a fixture's directory selects that fixture, a checker's file and
  fixtures select `checkers`, and the rest of the table says everything or
  nothing. The proof modules' mutation members (`mutation/...`) keep their
  own rule (tests/static/mutation_check.py): they are not in this table.

This is tested, not proved: tests/static/affected_test.py lists cases, checks
the rules that select nothing against the text of everything that could read
the path, and runs the whole table over the repository's files.
"""
import os
import re
import subprocess

ALL = 'all'
NONE = frozenset()
CHECKERS = 'checkers'

def pattern(glob):
    """A glob as a regular expression: `**` is any run of characters, `*` any
    run without a slash."""
    out, i = '', 0
    while i < len(glob):
        if glob.startswith('**', i):
            out += '.*'
            i += 2
        elif glob[i] == '*':
            out += '[^/]*'
            i += 1
        elif glob[i] == '?':
            out += '[^/]'
            i += 1
        else:
            out += re.escape(glob[i])
            i += 1
    return re.compile(out + r'\Z')


# One pass over the text, so a comment marker inside a string is not a
# comment and a quote inside a comment starts no string: a quoted string or a
# template literal is kept whole; a block or a line comment is the match.
# A string cannot run over a line end, so a quote the pass misreads (inside a
# regular expression literal) costs the rest of that line, not the file.
COMMENTS = re.compile(
    r"""(?P<text>'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*"|`(?:[^`\\]|\\.)*`)"""
    r"""|(?P<block>/\*.*?\*/)|(?P<line>//[^\n]*)""",
    re.DOTALL)


def strip_comments(text):
    """The text without its block and line comments (a comment may name a
    path it does not read), strings and template literals kept as they are.
    A block comment becomes a space, a line comment nothing."""
    return COMMENTS.sub(lambda found: found.group('text') or (' ' if found.group('block') else ''), text)


IMPORT = re.compile(
    r"""(?:\bfrom\s*|\bimport\s*\(\s*|\brequire\s*\(\s*|\bimport\s+)['"`](\.{1,2}/[^'"`$]*)['"`]""")
MODULE_SUFFIXES = ('.js', '.mjs', '.cjs')


class Tree:
    """The checkout the rules read: its e2e modules, and which reach which."""

    def __init__(self, root):
        self.root = root
        self._texts = None
        self._importers = None

    def exists(self, path):
        return os.path.exists(os.path.join(self.root, path))

    def isdir(self, path):
        return os.path.isdir(os.path.join(self.root, path))

    def texts(self):
        """Every module under e2e/ (path from the root -> text without comments)."""
        if self._texts is None:
            self._texts = {}
            base = os.path.join(self.root, 'e2e')
            for directory, _, names in os.walk(base):
                for name in sorted(names):
                    if name.endswith(MODULE_SUFFIXES):
                        path = os.path.relpath(os.path.join(directory, name), self.root)
                        with open(os.path.join(self.root, path), encoding='utf-8') as file:
                            self._texts[path] = strip_comments(file.read())
        return self._texts

    def specs(self):
        return sorted(path for path in self.texts() if path.endswith('.spec.js'))

    def importers(self):
        """module -> the modules under e2e/ that import it."""
        if self._importers is None:
            self._importers = {}
            for path, text in self.texts().items():
                for specifier in IMPORT.findall(text):
                    target = os.path.normpath(os.path.join(os.path.dirname(path), specifier))
                    if target not in self.texts() and self.exists(target + '.js'):
                        target += '.js'
                    self._importers.setdefault(target, set()).add(path)
        return self._importers

    def reaching(self, modules):
        """The specs that are one of `modules` or import one, however far."""
        seen, queue = set(modules), list(modules)
        while queue:
            for importer in self.importers().get(queue.pop(), ()):
                if importer not in seen:
                    seen.add(importer)
                    queue.append(importer)
        return {path for path in seen if path.endswith('.spec.js')}


# --- what a path selects of the e2e specs --------------------------------------

def e2e_modules(path, status, tree):
    """e2e/<module>.js: the specs that are it or reach it. A module no spec
    reaches (global-setup.js, which Playwright loads by name) and a deletion
    select every spec."""
    if status == 'D':
        return ALL
    reached = tree.reaching([path])
    return reached if reached else ALL


def e2e_assets(path, status, tree):
    """Anything else under e2e/ (a font, a JSON, an mp3): the specs reaching a
    module that names the file or the directory it is in; none named is all."""
    if status == 'D':
        return ALL
    return named_in_modules(path, tree)


def named_in_modules(path, tree, directory=None):
    """The specs reaching a module under e2e/ whose text names `path`'s file
    (or, when it is deeper than `directory`, the directory under it)."""
    needles = {os.path.basename(path)}
    parent = os.path.dirname(path)
    if directory and parent != directory and parent.startswith(directory + '/'):
        needles.add(parent[len(directory) + 1:].split('/')[0])
    named = [module for module, text in tree.texts().items() if any(needle in text for needle in needles)]
    if not named:
        return ALL
    reached = tree.reaching(named)
    return reached if reached else ALL


def e2e_by_name(path, status, tree):
    """A file outside e2e/ that specs read by a name they spell out
    (test/fixtures/*.epub)."""
    if status == 'D':
        return ALL
    return named_in_modules(path, tree, directory='test/fixtures')


# --- what a path selects of the static members -----------------------------------

def static_fixture(path, status, tree):
    """tests/static/accept/<name>/... or reject/<name>/...: that fixture."""
    verdict, name = path.split('/')[2:4]
    member = f'{verdict}/{name}'
    return frozenset([member]) if tree.isdir(f'tests/static/{member}') else ALL


def only_checkers(path, status, tree):
    return frozenset([CHECKERS])


def only_solver(path, status, tree):
    return frozenset(['solver'])


class Rule:
    def __init__(self, name, globs, e2e, static):
        self.name = name
        self.globs = globs
        self.matches = [pattern(glob) for glob in globs]
        self.e2e = e2e
        self.static = static

    def covers(self, path):
        return any(match.match(path) for match in self.matches)


#: First match wins. `ALL` and `NONE`, or a function (path, status, tree).
#: A rule that selects NONE of a kind is a claim that nothing of that kind
#: reads the path: `readers` in tests/static/affected_test.py checks it
#: against the text of what could.
RULES = [
    # The CI itself and the pins: a change to how the groups run, or to what
    # every one of them is built from, is a change to all of them.
    Rule('CI files', [
        '.github/workflows/check.yml', '.github/actions/**', '.github/bats-version',
        '.github/repository-version', 'tests/groups.json', 'tests/static/run.sh',
        'scripts/ci-groups.py', 'scripts/affected.py',
        'bats.toml', 'bats.lock', 'package.json', 'package-lock.json', 'playwright.config.js',
    ], ALL, ALL),
    # What the app is built from
    Rule('the app', ['src/**', 'assets/**', 'scripts/sync-clients.*'], ALL, ALL),
    # Notes nothing reads, and the workflows that are runs of their own
    Rule('docs and other workflows', [
        'README.md', 'CLAUDE.md', 'ANDROID.md', 'implementation-plan.md', 'plan.txt',
        'success.txt', 'ux-review/**', 'reports/**',
        # The agents' settings, rules, orchestration notes, agents and skills (#680):
        # no workflow, script or test reads `.claude/`
        '.claude/**',
        '.github/workflows/deploy.yml', '.github/workflows/mutation.yml',
        '.github/workflows/relock.yml', '.github/workflows/sync-identity.yml',
        '.github/workflows/sync-providers.yml', '.github/workflows/supersede.yml',
    ], NONE, NONE),
    # The hunt (quire#575): a dispatch-only workflow and its script, run by no group; its script's test is a checker
    Rule('the hunt', ['.github/workflows/hunt.yml', 'scripts/hunt.py'], NONE, only_checkers),
    # Tests of the build job (vitest on the wasm, the codec, the CSS reader, the
    # layout cap's node check, the version) and the home page, which the e2e
    # groups serve beside the app
    Rule('the build job\'s tests', [
        'test/*.js', 'vitest.config.js', 'tests/codec/**', 'tests/css-size/**',
        'tests/layout-cap/**', 'tests/version/**',
    ], NONE, NONE),
    Rule('test books', ['test/fixtures/**'], e2e_by_name, NONE),
    Rule('home page', ['homepage/**'], ALL, NONE),
    # The e2e suite: the specs it reaches; the static checkers that read e2e/
    Rule('e2e modules', ['e2e/*.js', 'e2e/**/*.js'], e2e_modules, only_checkers),
    Rule('e2e files', ['e2e/**'], e2e_assets, only_checkers),
    # The static tests
    Rule('a static fixture', ['tests/static/accept/*/**', 'tests/static/reject/*/**'], NONE, static_fixture),
    Rule('the solver fixtures', ['tests/static/solver.py', 'tests/static/solver/**'], NONE, only_solver),
    Rule('the static checkers', ['tests/static/**'], NONE, only_checkers),
]


class Selection:
    """What a change selects: ALL or a set of e2e specs, ALL or a set of static members."""

    def __init__(self, e2e=NONE, static=NONE):
        self.e2e, self.static = e2e, static

    def add(self, other):
        self.e2e = join(self.e2e, other.e2e)
        self.static = join(self.static, other.static)


def join(first, second):
    if first == ALL or second == ALL:
        return ALL
    return first | second


def classify(path, status, tree):
    """(rule name, Selection) of one changed path. A path no rule names selects
    everything."""
    for rule in RULES:
        if rule.covers(path):
            picked = [kind(path, status, tree) if callable(kind) else kind for kind in (rule.e2e, rule.static)]
            return rule.name, Selection(*picked)
    return 'unknown path', Selection(ALL, ALL)


def select(changes, tree):
    """(Selection, why) of a change, a list of (status, path). Nothing changed is
    a diff that cannot be explained, so it selects everything."""
    if not changes:
        return Selection(ALL, ALL), ['no change to go by: everything']
    total, why = Selection(), []
    for status, path in changes:
        name, picked = classify(path, status, tree)
        total.add(picked)
        why.append(f'{status} {path}: {name} -> e2e {describe(picked.e2e)}, static {describe(picked.static)}')
    return total, why


def describe(selected):
    if selected == ALL:
        return 'all'
    if not selected:
        return 'none'
    return ', '.join(sorted(os.path.basename(name) if name.endswith('.js') else name for name in selected))


def git_changes(base, root):
    """The paths changed since `base`: (status, path), a rename as its two paths."""
    out = subprocess.run(['git', 'diff', '--no-renames', '--name-status', '-z', base, 'HEAD'],
                         cwd=root, check=True, capture_output=True).stdout.decode('utf-8')
    tokens = out.split('\0')
    changes = []
    for i in range(0, len(tokens) - 1, 2):
        changes.append((tokens[i][:1], tokens[i + 1]))
    return changes


def plan(groups, changes, tree, mutation_runs):
    """What every group runs.

    `changes` is None for a run with nothing to compare with (everything runs),
    else (status, path) pairs. `mutation_runs(members)` says whether a group of
    mutation members has anything to run: their own rule, asked whatever
    `changes` is (it has its own base, and `False` for a run with none).

    Returns {'e2e': {group: bool}, 'static': {group: {'members': 'a b', 'bats': bool}},
    'why': [line]}."""
    if changes is None:
        picked, why = Selection(ALL, ALL), ['no base (a push, a merge group, a dispatch or the nightly run): everything']
    else:
        picked, why = select(changes, tree)
    selected_specs = picked.e2e
    result = {'e2e': {}, 'static': {}, 'why': why}
    for group, specs in groups['e2e'].items():
        result['e2e'][group] = selected_specs == ALL or any(f'e2e/{spec}' in selected_specs for spec in specs)
    for group, members in groups['static'].items():
        if all(member.startswith('mutation/') for member in members):
            run = mutation_runs(members)
            result['static'][group] = {'members': ' '.join(members) if run else '', 'bats': bool(run)}
            continue
        chosen = [member for member in members
                  if not member.startswith('mutation/') and (picked.static == ALL or member in picked.static)]
        needs_bats = any(member != CHECKERS for member in chosen)
        result['static'][group] = {'members': ' '.join(chosen), 'bats': needs_bats}
    return result
