#!/usr/bin/env python3
"""Tests of the rule that says which groups a change can affect (quire#619).

scripts/affected.py selects, from the paths of a change, the e2e specs and the
static members that can have a different result, and a path it does not know
selects everything. What is tested here:

* the graph of the e2e specs, on a small tree built for the purpose: a spec
  reaches what it imports, however far, by `import`, `import()` and
  `require`; a commented import is none; a module no spec reaches, an asset
  nobody names and a deletion select every spec;
* the cases in tests/static/affected/cases.json, on the real groups and the
  real specs: docs only, a spec only, a books module, a fixture only, the
  app's source, each file of the CI, the pins, an unknown path, an empty diff;
* the table over the repository: no spec and no fixture can be skipped by a
  change to itself, every file gets a rule or the fail-closed answer, and a
  change to every file is explained;
* the rules that select nothing for a kind (docs, the other workflows, the
  build job's tests, the home page for the static tests): nothing that could
  read the path names it (`Readers`), so the claim is checked against the
  text of the e2e suite, the static tests and the app's staloads, and not
  only believed. That is a test of the table, not a proof of it.

No bats and no patsopt: it reads files (and runs git on a repository of its own).

usage: python3 tests/static/affected_test.py
"""
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import affected as af  # noqa: E402

GROUPS = json.loads((ROOT / 'tests' / 'groups.json').read_text())
SKIPPED_DIRECTORIES = {'.git', 'node_modules', 'build', 'dist', 'bats_modules', 'test-results', 'playwright-report'}


def tracked_files():
    """Every file of the checkout a change could touch (no git needed)."""
    found = []
    for directory, names, files in os.walk(ROOT):
        names[:] = sorted(name for name in names if name not in SKIPPED_DIRECTORIES)
        for name in sorted(files):
            found.append(os.path.relpath(os.path.join(directory, name), ROOT))
    return found


def run_plan(changes, root=ROOT, groups=GROUPS, mutation=lambda members: False):
    return af.plan(groups, changes, af.Tree(str(root)), mutation)


def running(result):
    """(e2e groups that run, static members that run) of a plan."""
    groups = {group for group, run in result['e2e'].items() if run}
    members = set()
    for info in result['static'].values():
        members.update(info['members'].split())
    return groups, members


def non_mutation_members():
    return {member for members in GROUPS['static'].values() for member in members
            if not member.startswith('mutation/')}


class Graph(unittest.TestCase):
    """The import graph, on a tree of its own."""

    FILES = {
        'e2e/a.spec.js': "import { test } from './fixtures.js';\nimport { book } from './a-books.js';\n",
        'e2e/b.spec.js': "import { test } from './fixtures.js';\nconst { nested } = require('./sub/nested.js');\n",
        'e2e/c.spec.js': "import { test } from './fixtures.js';\nconst later = await import('./later.js');\n",
        'e2e/d.spec.js': "import './effect.js';\n// import { gone } from './commented.js';\n/* import { gone } from './block.js'; */\n",
        'e2e/fixtures.js': "export const test = 1;\n",
        'e2e/a-books.js': "import { zip } from './zip.js';\nconst font = new URL('./face.ttf', import.meta.url);\n",
        'e2e/zip.js': "export const zip = 1;\n",
        'e2e/sub/nested.js': "import { zip } from '../zip.js';\nconst data = 'old/9ce.json';\n",
        'e2e/later.js': "export const later = 1;\n",
        'e2e/effect.js': "export const effect = 1;\n",
        'e2e/commented.js': "export const gone = 1;\n",
        'e2e/block.js': "export const gone = 1;\n",
        'e2e/lonely.js': "export const alone = 1;\n",
        'e2e/face.ttf': 'font',
        'e2e/old/9ce.json': '{}',
        'e2e/unnamed.bin': 'bytes',
        'e2e/global-setup.js': "export default 1;\n",
    }

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        for path, text in self.FILES.items():
            full = Path(self.directory.name) / path
            full.parent.mkdir(parents=True, exist_ok=True)
            full.write_text(text)
        self.tree = af.Tree(self.directory.name)

    def selected(self, path, status='M'):
        name, picked = af.classify(path, status, self.tree)
        return picked.e2e

    def test_a_spec_is_itself(self):
        self.assertEqual(self.selected('e2e/a.spec.js'), {'e2e/a.spec.js'})

    def test_what_a_spec_imports_selects_it(self):
        self.assertEqual(self.selected('e2e/a-books.js'), {'e2e/a.spec.js'})

    def test_however_far(self):
        # zip.js is imported by a-books.js (a.spec) and by sub/nested.js (b.spec)
        self.assertEqual(self.selected('e2e/zip.js'), {'e2e/a.spec.js', 'e2e/b.spec.js'})

    def test_a_shared_helper_selects_every_spec_that_imports_it(self):
        self.assertEqual(self.selected('e2e/fixtures.js'), {'e2e/a.spec.js', 'e2e/b.spec.js', 'e2e/c.spec.js'})

    def test_require_and_dynamic_import_and_side_effect_import(self):
        self.assertEqual(self.selected('e2e/sub/nested.js'), {'e2e/b.spec.js'})
        self.assertEqual(self.selected('e2e/later.js'), {'e2e/c.spec.js'})
        self.assertEqual(self.selected('e2e/effect.js'), {'e2e/d.spec.js'})

    def test_a_commented_import_is_none(self):
        self.assertEqual(self.selected('e2e/commented.js'), af.ALL)
        self.assertEqual(self.selected('e2e/block.js'), af.ALL)

    def test_a_module_no_spec_reaches_selects_every_spec(self):
        self.assertEqual(self.selected('e2e/lonely.js'), af.ALL)
        self.assertEqual(self.selected('e2e/global-setup.js'), af.ALL)

    def test_an_asset_a_module_names(self):
        self.assertEqual(self.selected('e2e/face.ttf'), {'e2e/a.spec.js'})

    def test_an_asset_by_the_directory_a_module_names(self):
        self.assertEqual(self.selected('e2e/old/9ce.json'), {'e2e/b.spec.js'})

    def test_an_asset_nobody_names_selects_every_spec(self):
        self.assertEqual(self.selected('e2e/unnamed.bin'), af.ALL)

    def test_a_deletion_selects_every_spec(self):
        self.assertEqual(self.selected('e2e/a-books.js', 'D'), af.ALL)
        self.assertEqual(self.selected('e2e/face.ttf', 'D'), af.ALL)

    def test_a_new_module_nothing_imports_yet_selects_every_spec(self):
        self.assertEqual(self.selected('e2e/brand-new.js', 'A'), af.ALL)

    def test_comments_are_dropped_and_strings_with_slashes_are_not(self):
        text = af.strip_comments("a(); // note\nconst u = 'https://x.test/y'; /* b */ c();\n")
        self.assertIn('https://x.test/y', text)
        self.assertNotIn('note', text)
        self.assertNotIn(' b ', text)


class StripComments(unittest.TestCase):
    """strip_comments and the import pattern on the text shapes that can
    hide an import (#656)."""

    def imports(self, text):
        return af.IMPORT.findall(af.strip_comments(text))

    def test_a_glob_in_a_string_starts_no_block_comment(self):
        text = "const files = 'e2e/*.js';\nimport { book } from './books.js';\nconst end = '*/';\n"
        self.assertEqual(self.imports(text), ['./books.js'])

    def test_a_glob_in_a_string_before_a_real_block_comment(self):
        text = "const g = 'e2e/*.js'; import './x.js'; /* c */ y();\n"
        self.assertEqual(self.imports(text), ['./x.js'])
        self.assertNotIn(' c ', af.strip_comments(text))

    def test_a_double_quoted_and_a_template_string_are_kept(self):
        text = 'const a = "x/*y"; const b = `p//q`; import "./z.js";\n'
        stripped = af.strip_comments(text)
        self.assertIn('"x/*y"', stripped)
        self.assertIn('`p//q`', stripped)
        self.assertEqual(self.imports(text), ['./z.js'])

    def test_a_line_comment_marker_in_a_string_is_not_a_comment(self):
        self.assertEqual(self.imports("const u = 'a//b'; import './x.js'\n"), ['./x.js'])

    def test_a_quote_in_a_comment_starts_no_string(self):
        text = "// it's here\nimport './x.js';\n/* don't */ import './y.js';\n"
        self.assertEqual(self.imports(text), ['./x.js', './y.js'])

    def test_a_commented_import_is_dropped_whatever_the_comment(self):
        text = "// import './a.js'\n/* import './b.js'; */\n/*\n * import './c.js'\n */\nimport './d.js';\n"
        self.assertEqual(self.imports(text), ['./d.js'])

    def test_a_block_comment_ends_at_the_first_close(self):
        self.assertEqual(self.imports("/* a */ import './x.js'; /* b */\n"), ['./x.js'])

    def test_a_trailing_line_comment_keeps_the_code_before_it(self):
        self.assertEqual(self.imports("import './x.js'; // import './y.js'\n"), ['./x.js'])

    def test_a_template_literal_without_substitution_is_an_import(self):
        self.assertEqual(self.imports("const m = await import(`./c.js`);\nrequire(`./d.js`);\n"), ['./c.js', './d.js'])

    def test_a_template_literal_with_substitution_is_not_a_static_specifier(self):
        # not seen: nothing in e2e/ writes one (a gap of the rule, not a pass)
        self.assertEqual(self.imports("await import(`./book-${name}.js`);\n"), [])

    def test_a_misread_quote_costs_its_line_not_the_file(self):
        text = "const quote = /'/; const x = 1;\nimport './x.js';\n"
        self.assertEqual(self.imports(text), ['./x.js'])


class Workflow(unittest.TestCase):
    """The jobs read the plan so that a group it does not name is not
    skipped (#656). In an expression `null == false` is true (a loose
    comparison turns both into 0), so `!= false` would skip a missing group;
    the text of the entry, 'null' against 'false', tells them apart. This
    reads the workflow's text: the expression itself runs only on GitHub."""

    TEXT = (ROOT / '.github' / 'workflows' / 'check.yml').read_text()

    def test_the_plan_has_an_entry_for_every_group(self):
        result = run_plan([('M', 'README.md')])
        self.assertEqual(sorted(result['e2e']), sorted(GROUPS['e2e']))
        self.assertEqual(sorted(result['static']), sorted(GROUPS['static']))

    def test_an_e2e_group_is_skipped_only_when_the_plan_says_false(self):
        reads = re.findall(r"\$\{\{[^}]*e2e_run\)\[matrix\.group\][^}]*\}\}", self.TEXT)
        self.assertEqual(len(reads), 1)
        self.assertIn("toJSON(fromJSON(needs.plan.outputs.e2e_run)[matrix.group]) == 'false' && 'no' || 'yes'", reads[0])

    def test_no_job_reads_a_group_of_the_plan_as_a_bare_truth_value(self):
        for read in re.findall(r"[^\n]*_run\)\[matrix\.group\][^\n]*", self.TEXT):
            with self.subTest(read):
                self.assertTrue("toJSON(" in read or ".members" in read or ".bats" in read, read)

    def test_a_static_group_the_plan_does_not_name_fails_its_job(self):
        self.assertIn("if: toJSON(fromJSON(needs.plan.outputs.static_run)[matrix.group]) == 'null'", self.TEXT)
        step = self.TEXT.index('- name: The plan names this group')
        self.assertIn('exit 1', self.TEXT[step:step + 600])


    def job(self, name):
        """The text of one job of check.yml (its block under `jobs:`)."""
        found = re.search(rf'(?ms)^  {re.escape(name)}:\n(.*?)(?=^  [a-z-]+:\n|\Z)', self.TEXT)
        self.assertIsNotNone(found, name)
        return found.group(1)

    def test_the_build_the_android_job_and_the_release_do_not_read_the_plan(self):
        for name in ('build', 'android', 'play-internal'):
            with self.subTest(name):
                self.assertNotIn('needs.plan', self.job(name))
                self.assertNotIn('plan.outputs', self.job(name))

    def test_the_build_and_the_android_job_are_never_skipped_by_the_plan(self):
        """Android's required contexts exist only if the job runs, and it needs the
        build's artifact: neither has an `if` but the build's `destroyed` one."""
        self.assertEqual(re.findall(r'(?m)^    if: .*$', self.job('build')),
                         ["    if: github.event.action != 'destroyed'"])
        self.assertEqual(re.findall(r'(?m)^    if: .*$', self.job('android')), [])
        self.assertIn('needs: build', self.job('android'))

    def test_a_merge_group_plans_the_whole_check(self):
        scope = self.job('plan')[self.job('plan').index('id: scope'):]
        self.assertRegex(scope, r'merge_group\) base=\$\(git rev-parse HEAD\^1\); full=full ;;')
        self.assertIn('scripts/ci-groups.py plan $base $full', scope)

    def test_the_whole_plan_ignores_the_base(self):
        spec = importlib.util.spec_from_file_location('ci_groups', ROOT / 'scripts' / 'ci-groups.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with patch.object(module.selection, 'git_changes', side_effect=AssertionError('the diff was read')):
            result = module.plan(GROUPS, 'none', full=True)
        self.assertEqual(set(result['e2e'].values()), {True})
        groups, members = running(result)
        self.assertEqual(members, non_mutation_members())


class Diff(unittest.TestCase):
    """The paths a change touched, as git says them (-z: any name).

    tests/static/run.sh points git at the checkout's repository (GIT_DIR, for the
    app's version): a repository made here must not see it, or `git init` and
    `git commit` act on the checkout's own, so the environment loses every GIT_*
    variable and the test refuses to go on if git does not name its own directory.
    """

    def setUp(self):
        if shutil.which('git') is None:
            self.skipTest('no git')
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        environment = patch.dict(os.environ)
        environment.start()
        self.addCleanup(environment.stop)
        for name in [name for name in os.environ if name.startswith('GIT_')]:
            del os.environ[name]
        self.git('init', '-q')
        top = subprocess.run(['git', 'rev-parse', '--show-toplevel'], cwd=self.directory.name,
                             check=True, capture_output=True).stdout.decode().strip()
        self.assertEqual(os.path.realpath(top), os.path.realpath(self.directory.name))

    def git(self, *arguments):
        subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@t', *arguments],
                       cwd=self.directory.name, check=True, capture_output=True)

    def write(self, path, text):
        full = Path(self.directory.name) / path
        full.parent.mkdir(parents=True, exist_ok=True)
        full.write_text(text)

    def test_added_modified_deleted_and_renamed_paths(self):
        self.write('keep.txt', 'one\n')
        self.write('gone.txt', 'two\n')
        self.write('old name.txt', 'a long enough text that git sees the rename\n' * 5)
        self.git('add', '.')
        self.git('commit', '-q', '-m', 'base')
        self.write('keep.txt', 'changed\n')
        self.write('new/\u00e9 new.txt', 'x\n')
        (Path(self.directory.name) / 'gone.txt').unlink()
        (Path(self.directory.name) / 'old name.txt').rename(Path(self.directory.name) / 'new name.txt')
        self.git('add', '-A')
        self.git('commit', '-q', '-m', 'change')
        got = sorted(af.git_changes('HEAD~1', self.directory.name))
        # a rename is its two paths: the old one is gone, the new one is added
        self.assertEqual(got, [('A', 'new name.txt'), ('A', 'new/\u00e9 new.txt'), ('D', 'gone.txt'),
                               ('D', 'old name.txt'), ('M', 'keep.txt')])

    def test_a_base_git_does_not_know_is_an_error_not_an_empty_diff(self):
        self.write('a.txt', 'a\n')
        self.git('add', '.')
        self.git('commit', '-q', '-m', 'base')
        with self.assertRaises(subprocess.CalledProcessError):
            af.git_changes('no-such-revision', self.directory.name)


class Cases(unittest.TestCase):
    """tests/static/affected/cases.json, on the real groups and specs."""

    def test_cases(self):
        cases = json.loads((ROOT / 'tests' / 'static' / 'affected' / 'cases.json').read_text())
        self.assertGreaterEqual(len(cases), 30)
        for case in cases:
            with self.subTest(case['name']):
                result = run_plan([tuple(change) for change in case['changes']])
                groups, members = running(result)
                want = case['e2e']
                if want == 'all':
                    self.assertEqual(groups, set(GROUPS['e2e']))
                elif want == 'none':
                    self.assertEqual(groups, set())
                else:
                    self.assertEqual(groups, set(want))
                want = case['static']
                if want == 'all':
                    self.assertEqual(members, non_mutation_members())
                elif want == 'none':
                    self.assertEqual(members, set())
                else:
                    self.assertEqual(members, set(want))

    def test_no_base_runs_everything_but_the_mutation_groups(self):
        result = run_plan(None)
        groups, members = running(result)
        self.assertEqual(groups, set(GROUPS['e2e']))
        self.assertEqual(members, non_mutation_members())

    def test_the_mutation_groups_are_asked_when_the_rest_runs_whole(self):
        """The merge group runs the e2e and static groups whole and the mutation groups by their rule."""
        result = run_plan(None, mutation=lambda members: members[0] == 'mutation/chunk')
        self.assertEqual(result['static']['mutation-chunk']['members'], 'mutation/chunk')
        self.assertEqual(result['static']['mutation-crc-1']['members'], '')
        self.assertEqual(set(result['e2e'].values()), {True})

    def test_the_mutation_rule_decides_its_groups_only(self):
        asked = []

        def mutation(members):
            asked.append(members)
            return members[0] == 'mutation/chunk'
        result = run_plan([('M', 'README.md')], mutation=mutation)
        self.assertEqual(result['static']['mutation-chunk'], {'members': 'mutation/chunk', 'bats': True})
        self.assertEqual(result['static']['mutation-crc-1'], {'members': '', 'bats': False})
        self.assertEqual(len(asked), sum(1 for members in GROUPS['static'].values()
                                         if all(m.startswith('mutation/') for m in members)))
        self.assertEqual(running(result)[1], {'mutation/chunk'})

    def test_checkers_alone_need_no_compiler(self):
        result = run_plan([('M', 'tests/static/ids.py')])
        self.assertEqual(result['static']['app'], {'members': 'checkers', 'bats': False})
        self.assertEqual(result['static']['accepts'], {'members': '', 'bats': False})

    def test_a_fixture_needs_the_compiler_in_its_own_group_only(self):
        result = run_plan([('M', 'tests/static/accept/clip-last/expect')])
        own = next(group for group, members in GROUPS['static'].items() if 'accept/clip-last' in members)
        for group, plan in result['static'].items():
            with self.subTest(group):
                if group == own:
                    self.assertEqual(plan, {'members': 'accept/clip-last', 'bats': True})
                else:
                    self.assertEqual(plan['members'], '')


class Table(unittest.TestCase):
    """The table over the repository."""

    def test_every_spec_is_selected_by_a_change_to_itself(self):
        for group, specs in GROUPS['e2e'].items():
            for spec in specs:
                with self.subTest(spec):
                    groups, _ = running(run_plan([('M', f'e2e/{spec}')]))
                    self.assertIn(group, groups)

    def test_every_fixture_is_selected_by_a_change_to_itself(self):
        for group, members in GROUPS['static'].items():
            for member in members:
                if member.startswith(('accept/', 'reject/')):
                    with self.subTest(member):
                        result = run_plan([('M', f'tests/static/{member}/snippet.bats')])
                        self.assertIn(member, result['static'][group]['members'].split())

    def test_every_file_of_the_checkout_is_explained(self):
        unknown, total = [], 0
        tree = af.Tree(str(ROOT))
        for path in tracked_files():
            total += 1
            name, picked = af.classify(path, 'M', tree)
            if name == 'unknown path':
                unknown.append(path)
        print(f'{total} files, {len(unknown)} no rule names (they select everything)', file=sys.stderr)
        self.assertGreater(total, 300)

    def test_a_change_to_a_ci_file_selects_everything(self):
        for path in ('.github/workflows/check.yml', '.github/actions/build-cache/action.yml',
                     'tests/groups.json', 'scripts/ci-groups.py', 'scripts/affected.py',
                     'tests/static/run.sh', 'bats.lock', 'bats.toml', '.github/bats-version'):
            with self.subTest(path):
                name, picked = af.classify(path, 'M', af.Tree(str(ROOT)))
                self.assertEqual((picked.e2e, picked.static), (af.ALL, af.ALL))

    def test_the_mutation_files_are_not_a_fixture(self):
        for path in ('tests/static/mutation_check.py', 'tests/static/mutation_known.txt'):
            with self.subTest(path):
                name, picked = af.classify(path, 'M', af.Tree(str(ROOT)))
                self.assertEqual(picked.static, frozenset(['checkers']))

    def test_the_proofs_audit_selects_its_checker_and_the_fixtures_it_names(self):
        for path in ('tests/static/proofs_audit.py', 'tests/static/proofs_audit_test.py',
                     'tests/static/proofs_audit_verdicts.txt', 'tests/static/proof_sources.py'):
            with self.subTest(path):
                name, picked = af.classify(path, 'M', af.Tree(str(ROOT)))
                self.assertEqual((picked.e2e, picked.static), (af.NONE, frozenset(['checkers', 'solver'])))


class Readers(unittest.TestCase):
    """A rule that selects nothing for a kind says nothing of that kind reads the
    path. Checked against the text of what could."""

    def files_of(self, rule):
        found = []
        for path in tracked_files():
            if rule.covers(path):
                found.append(path)
        return found

    def names_of(self, rule):
        """What a reader would call the files of a rule: their paths, their
        directory, and (for a rule of single files) their names."""
        names = set()
        for glob in rule.globs:
            if glob.endswith('/**'):
                names.add(glob[:-2])
            elif '*' not in glob:
                names.add(glob)
                names.add(os.path.basename(glob))
        for path in self.files_of(rule):
            names.add(path)
            if not any(glob.endswith('/**') for glob in rule.globs):
                names.add(os.path.basename(path))
        return {name for name in names if name}

    def e2e_readers(self):
        """The text the e2e suite is made of."""
        texts = {path: text for path, text in af.Tree(str(ROOT)).texts().items()}
        config = ROOT / 'playwright.config.js'
        texts['playwright.config.js'] = af.strip_comments(config.read_text())
        return texts

    def static_readers(self):
        """The text the static members read: the checkers and the runner, the
        fixtures' own files being snippets of the app and the app's staloads."""
        texts = {}
        for path in tracked_files():
            # mutation_check.py reads the workflows that pin the setup action to say
            # which mutation groups a change selects: that is the mutation groups' own
            # rule, which this table leaves as it is, and the member that runs the
            # checker (mutation_test.py) reads a temporary tree, not these files
            if path.startswith('tests/static/') and path.endswith(('.py', '.sh')) \
                    and not path.startswith(('tests/static/accept/', 'tests/static/reject/', 'tests/static/affected_test')) \
                    and path != 'tests/static/mutation_check.py':
                text = (ROOT / path).read_text(errors='replace')
                texts[path] = af.strip_comments(text) if path.endswith('.js') else strip_hash_comments(text)
            if path.startswith('src/') and path.endswith('.bats'):
                lines = [line for line in (ROOT / path).read_text(errors='replace').splitlines()
                         if re.search(r'\bstaload\b|\binclude\b|\bdynload\b', line)]
                texts[path] = '\n'.join(lines)
        texts['bats.toml'] = (ROOT / 'bats.toml').read_text()
        return texts

    def mentions(self, texts, names):
        named = re.compile(r'(?<![A-Za-z0-9_.-])(' + '|'.join(re.escape(name) for name in sorted(names)) + r')(?![A-Za-z0-9_-])')
        return [f'{path} names {name}' for path, text in texts.items() for name in sorted(set(named.findall(text)))]

    def test_what_selects_no_spec_is_named_by_none(self):
        readers = self.e2e_readers()
        for rule in af.RULES:
            if rule.e2e == af.NONE:
                with self.subTest(rule.name):
                    self.assertEqual(self.mentions(readers, self.names_of(rule)), [])

    def test_what_selects_no_static_member_is_named_by_none(self):
        readers = self.static_readers()
        for rule in af.RULES:
            if rule.static == af.NONE:
                with self.subTest(rule.name):
                    self.assertEqual(self.mentions(readers, self.names_of(rule)), [])

    def test_the_scan_sees_a_reader(self):
        """The scan fails on a file that is named: it is not vacuous."""
        rule = af.Rule('fake', ['home' + 'page/**'], af.NONE, af.NONE)
        hits = self.mentions(self.e2e_readers(), self.names_of(rule))
        self.assertTrue(any('about.spec.js' in hit for hit in hits), hits)


def strip_hash_comments(text):
    return re.sub(r'(?m)(^|\s)#[^\n]*$', r'\1', text)


if __name__ == '__main__':
    unittest.main(verbosity=1)
