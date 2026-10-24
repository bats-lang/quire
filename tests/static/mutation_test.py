#!/usr/bin/env python3
"""Tests of the mutation checker itself (mutation_check.py, quire#594).

The checker's job is to flag a lemma that proves nothing, so it is tested on
tiny lemmas whose verdict is known: an honest one, whose false variants a
compiler rejects, and a vacuous one, whose false variants it accepts. The
compiler is a stand-in (a script that rejects a mutant of every lemma not
listed in `vacuous.txt`, with the error line patsopt gives), so the test
needs no bats and no patsopt; the real compiler is the `mutation` member of
tests/static/run.sh. Also tested: the operators on statements, the
declaration and primplement edit of a recursive public lemma, and the choice
of lemmas by a git diff.

usage: python3 tests/static/mutation_test.py
"""
import io
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mutation_check as mc  # noqa: E402

MODULE = """\
datasort bytes = bnil | bcons of (int, bytes)
dataprop LE(int, int) =
  | {a:int} LE_refl(a, a)

(* an honest lemma: its false variants are false *)
prfun le_trans {a,b,c:int} (first: LE(a, b), second: LE(b, c)): LE(a, c) =
  case+ first of LE_refl() => second

(* a lemma that calls the first *)
prfn le_twice {a,b:int} (step: LE(a, b)): LE(a, b) =
  le_trans(LE_refl(), step)

prfn vacuous_guard {a:int} (known: LE(a, a)): [a == a] void = ()

prfn exists_len {n:nat} (): [m:nat | m >= 3] LE(m, n) = ()

prfn tuple_of {a:int} (): (LE(a, a), LE(a, a)) = (LE_refl(), LE_refl())

#pub prfun grow {a:int} (x: LE(a, a)): LE(a, a)

primplement grow {a} (x) = grow(x)

#pub prfun named_args {a:int} (step: LE(a, a), other: LE(a, a)): LE(a, a)

primplement named_args {a} (step, other) = step
"""


class Operators(unittest.TestCase):
    def statements(self, result, sorts):
        return {v.statement for v in mc.mutate(result, sorts)}

    def test_probe_and_guard(self):
        out = self.statements('[a == b] void', {'a': 'int', 'b': 'int'})
        self.assertIn('[1 == 2] void', out)
        self.assertIn('[a == (b) + 1 ] void', out)

    def test_int_arguments_get_plus_one(self):
        out = self.statements('LE(a, c)', {'a': 'int', 'c': 'nat'})
        self.assertEqual(out, {'LE((a) + 1, c)', 'LE(a, (c) + 1)'})

    def test_byte_strings_get_a_byte(self):
        out = self.statements('APPEND(x, y, z)', {'x': 'bytes', 'y': 'bytes', 'z': 'bytes'})
        self.assertEqual(len(out), 3)
        self.assertIn('APPEND(x, y, bcons(0, z))', out)

    def test_other_sorts_get_a_fresh_variable(self):
        variants = mc.mutate('EQ(cells, other)', {'cells': 'cells', 'other': 'cells'})
        self.assertEqual({v.statement for v in variants}, {'EQ(cells, mutant_fresh)', 'EQ(mutant_fresh, other)'})
        self.assertTrue(all(v.extra == '{mutant_fresh: cells}' for v in variants))

    def test_existential_prefix_binds_sorts_and_tightens_bounds(self):
        variants = mc.mutate('[m: nat | m >= 3] LE(m, n)', {'n': 'int'})
        out = {v.statement for v in variants}
        self.assertIn('[m: nat | m >= 4] LE(m, n)', out)
        self.assertIn('[m: nat | m >= 3] LE(m, (n) + 1)', out)
        self.assertIn('[m: nat | m >= 3] LE((m) + 1, n)', out)

    def test_tuple_parts(self):
        out = self.statements('(LE(a, a), LE(a, b))', {'a': 'int', 'b': 'int'})
        self.assertIn('(LE((a) + 1, a), LE(a, b))', out)
        self.assertIn('(LE(a, a), LE(a, (b) + 1))', out)

    def test_bound_shift(self):
        out = self.statements('[a < b] void', {'a': 'int', 'b': 'int'})
        self.assertIn('[(a) + 1  < b] void', out)

    def test_no_duplicates(self):
        variants = mc.mutate('LE(a, a)', {'a': 'int'})
        self.assertEqual(len(variants), len({v.statement for v in variants}))


class Shards(unittest.TestCase):
    def test_the_parts_partition_the_names(self):
        weights = [(f'lemma{i}', 1 + (i * 7) % 5) for i in range(23)]
        for count in (1, 2, 3, 5, 8):
            parts = mc.partition(weights, count)
            self.assertEqual(len(parts), count)
            self.assertEqual(sum(len(p) for p in parts), len(weights))  # no overlap
            self.assertEqual(set().union(*parts), {n for n, _ in weights})  # everything

    def test_the_parts_are_balanced_by_weight(self):
        weights = [(f'l{i}', w) for i, w in enumerate([9, 8, 7, 6, 5, 4, 3, 2, 1, 1])]
        totals = [sum(dict(weights)[n] for n in part) for part in mc.partition(weights, 3)]
        self.assertLessEqual(max(totals) - min(totals), 9)  # never worse than the heaviest lemma
        self.assertLessEqual(max(totals), 16)

    def test_the_order_given_does_not_matter(self):
        weights = [(f'lemma{i}', 1 + i % 4) for i in range(17)]
        self.assertEqual(mc.partition(weights, 4), mc.partition(list(reversed(weights)), 4))

    def test_a_module_split_in_shards_is_the_module(self):
        lines = MODULE.split('\n')
        whole = mc.selected_names('/nonexistent', 'src/m.bats', lines, set(), None, None)
        parts = [mc.selected_names('/nonexistent', 'src/m.bats', lines, set(), None, (i, 3)) for i in (1, 2, 3)]
        self.assertEqual(set().union(*parts), whole)
        self.assertEqual(sum(len(p) for p in parts), len(whole))

    def test_member_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / 'tests' / 'static').mkdir(parents=True)
            (Path(tmp) / mc.MODULES_FILE).write_text('# c\nsrc/crc.bats 3\nsrc/seq.bats\nsrc/small.bats 1 smoke\n')
            self.assertEqual(mc.parse_member(tmp, 'mutation/crc-part2of3'), ('src/crc.bats', 2, 3))
            self.assertEqual(mc.parse_member(tmp, 'mutation/seq'), ('src/seq.bats', 1, 1))
            self.assertEqual(mc.read_modules(tmp)[2], ('src/small.bats', 1, True))
            with self.assertRaises(KeyError):
                mc.parse_member(tmp, 'mutation/crc-part4of3')


class Declarations(unittest.TestCase):
    def lemmas(self, text=MODULE):
        lines = text.split('\n')
        return mc.lemmas_of(mc.decls(lines, mc.strip(text).split('\n')))

    def test_lemmas_found(self):
        self.assertEqual([l.name for l in self.lemmas()],
                         ['le_trans', 'le_twice', 'vacuous_guard', 'exists_len', 'tuple_of', 'grow', 'named_args'])

    def test_statement_and_sorts(self):
        by_name = {l.name: l for l in self.lemmas()}
        self.assertEqual(by_name['le_trans'].decl.result, 'LE(a, c)')
        self.assertEqual(by_name['le_trans'].decl.sorts(), {'a': 'int', 'b': 'int', 'c': 'int'})
        self.assertEqual(by_name['grow'].kind, 'public')
        self.assertTrue(by_name['grow'].parts() is not None and by_name['grow'].inplace)

    def test_a_recursive_public_lemma_is_edited_in_place_with_its_fresh_quantifier(self):
        lines = MODULE.split('\n')
        lemma = {l.name: l for l in self.lemmas()}['grow']
        lemma.parts()
        mutant = mc.Mutant(1, lemma, mc.Variant('arg1:fresh', 'LE(mutant_fresh, a)', '{mutant_fresh: int}'), False)
        edited, (first, last) = mc.inplace_edit(lines, lemma, mutant)
        text = '\n'.join(edited)
        self.assertIn('#pub prfun grow {a:int} {mutant_fresh: int} (x: LE(a, a)): LE(mutant_fresh, a)', text)
        self.assertIn('primplement grow {a} {mutant_fresh: int} (x) = grow(x)', text)
        self.assertTrue(first <= text.split('\n').index('primplement grow {a} {mutant_fresh: int} (x) = grow(x)') + 1 <= last)

    def test_a_declaration_that_names_its_arguments_gives_a_copy_that_names_each_once(self):
        lemmas, mutants = mc.build(MODULE.split('\n'), {'named_args'})
        text = mc.text_of(mutants[0])
        self.assertIn('(step: LE(a, a), other: LE(a, a))', text)
        self.assertNotIn('step: step', text)

    def test_a_copy_is_named_and_keeps_the_body(self):
        lemma = self.lemmas()[0]
        lemmas, mutants = mc.build(MODULE.split('\n'), set())
        text = mc.text_of(mutants[0])
        self.assertIn('prfn _mutant_1_le_trans', text) if lemma.decl.keyword == 'prfn' else self.assertIn('_mutant_1_le_trans', text)
        self.assertIn('case+ first of LE_refl() => second', text)


class FakeCompiler(unittest.TestCase):
    """A stand-in `bats check`: it rejects a mutant (not a control) of every lemma
    that vacuous.txt does not list, reporting the line of the mutant as patsopt does."""

    SCRIPT = '''#!/usr/bin/env python3
import re, sys
from pathlib import Path
text = Path("src/m.bats").read_text()
vacuous = set(Path("vacuous.txt").read_text().split()) if Path("vacuous.txt").exists() else set()
broken = set(Path("broken.txt").read_text().split()) if Path("broken.txt").exists() else set()
failed = False
for number, line in enumerate(text.split("\\n"), 1):
    m = re.match(r"\\(\\* (control|mutant) .*of (\\w+) \\*\\)$", line)
    if not m:
        continue
    kind, name = m.groups()
    if kind == "control" and name in broken:
        print(f"src/m.bats: {number}(line={number}, offs=1) -- {number}(line={number}, offs=5): error(3): control refused")
        failed = True
    elif kind == "mutant" and name not in vacuous and name not in broken:
        print(f"src/m.bats: {number + 1}(line={number + 1}, offs=1) -- {number + 1}(line={number + 1}, offs=5): error(3): unsolved constraint")
        failed = True
sys.exit(1 if failed else 0)
'''

    def run_checker(self, vacuous=(), broken=(), extra=()):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            (work / 'src').mkdir()
            (work / 'src' / 'm.bats').write_text(MODULE)
            (work / 'vacuous.txt').write_text('\n'.join(vacuous))
            (work / 'broken.txt').write_text('\n'.join(broken))
            fake = work / 'fake-check'
            fake.write_text(self.SCRIPT)
            fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
            os.environ['BATS_CHECK'] = str(fake)
            out = io.StringIO()
            with redirect_stdout(out):
                code = mc.main(['--run', str(work), '--root', str(work), *extra, 'src/m.bats'])
            restored = (work / 'src' / 'm.bats').read_text() == MODULE
        return code, out.getvalue(), restored

    def test_honest_lemmas_pass(self):
        code, out, restored = self.run_checker()
        self.assertEqual(code, 0, out)
        self.assertNotIn('ACCEPTED', out)
        self.assertIn('0 accepted, 0 broken, 0 controls failed', out)
        self.assertTrue(restored)

    def test_a_vacuous_lemma_is_flagged(self):
        code, out, _ = self.run_checker(vacuous=['le_trans'])
        self.assertEqual(code, 1, out)
        flagged = [l for l in out.splitlines() if l.startswith('ACCEPTED')]
        self.assertTrue(flagged and all('le_trans' in l for l in flagged), out)
        self.assertTrue(any(l.startswith('REJECTED') and 'le_twice' in l for l in out.splitlines()))

    def test_a_vacuous_lemma_explained_is_known(self):
        with tempfile.NamedTemporaryFile('w', suffix='.txt') as known:
            known.write('src/m.bats | le_trans | * | the mutants are equivalent\n')
            known.flush()
            code, out, _ = self.run_checker(vacuous=['le_trans'], extra=['--known', known.name])
        self.assertEqual(code, 0, out)
        self.assertIn('KNOWN', out)

    def test_known_covers_only_its_operator(self):
        with tempfile.NamedTemporaryFile('w', suffix='.txt') as known:
            known.write('src/m.bats | le_trans | arg2+1 | explained\n')
            known.flush()
            code, out, _ = self.run_checker(vacuous=['le_trans'], extra=['--known', known.name])
        self.assertEqual(code, 1, out)
        self.assertIn('KNOWN', out)
        self.assertIn('ACCEPTED', out)

    def test_a_control_that_fails_is_reported_not_skipped_quietly(self):
        code, out, _ = self.run_checker(broken=['le_twice'])
        self.assertEqual(code, 1, out)
        self.assertIn('HARNESS  src/m.bats le_twice: control CONTROL-FAILED', out)

    def test_only_the_named_lemma(self):
        code, out, _ = self.run_checker(vacuous=['le_trans'], extra=['--only', 'le_twice'])
        self.assertEqual(code, 0, out)
        self.assertNotIn('le_trans', out)


class Selection(unittest.TestCase):
    def setUp(self):
        # run.sh points git at the checkout (GIT_DIR); these tests make repositories of their own
        self.saved = {k: os.environ.pop(k) for k in list(os.environ) if k.startswith('GIT_')}
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / 'src').mkdir()
        (self.root / 'src' / 'm.bats').write_text(MODULE)
        (self.root / 'src' / 'other.bats').write_text(
            'prfn uses_le {a:int} (x: LE(a, a)): LE(a, a) = x\n\nprfn alone {a:int} (): [a == a] void = ()\n')
        self.git('init', '-q')
        self.git('add', '.')
        self.git('-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-q', '-m', 'one')

    def tearDown(self):
        os.environ.update(self.saved)
        self.tmp.cleanup()

    def git(self, *args):
        subprocess.run(['git', '-C', str(self.root), *args], check=True, capture_output=True)

    def edit(self, file, old, new):
        path = self.root / file
        path.write_text(path.read_text().replace(old, new))

    def select(self, file='src/m.bats'):
        return mc.select_by_diff(self.root, 'HEAD', file)

    def test_nothing_changed_selects_nothing(self):
        self.assertEqual(self.select(), set())

    def test_a_comment_selects_nothing(self):
        self.edit('src/m.bats', '(* an honest lemma: its false variants are false *)', '(* an honest lemma *)')
        self.assertEqual(self.select(), set())

    def test_a_lemma_and_its_callers(self):
        self.edit('src/m.bats', 'case+ first of LE_refl() => second', 'case+ first of LE_refl() => (second)')
        self.assertEqual(self.select(), {'le_trans', 'le_twice'})

    def test_other_lemmas_are_left_alone(self):
        self.edit('src/m.bats', 'prfn tuple_of {a:int} (): (LE(a, a), LE(a, a))', 'prfn tuple_of {a:int} (): (LE(a, a), LE(a, a))  ')
        selected = self.select()
        self.assertIn('tuple_of', selected)
        self.assertNotIn('vacuous_guard', selected)

    def test_a_change_outside_the_lemmas_selects_all(self):
        self.edit('src/m.bats', '| {a:int} LE_refl(a, a)', '| {a:int} LE_refl(a, a)\n  | {a:int} LE_again(a, a)')
        self.assertIsNone(self.select())

    def test_a_name_declared_in_the_diff_reaches_other_files(self):
        self.edit('src/m.bats', 'LE(a, b), second: LE(b, c)): LE(a, c)', 'LE(a, b), second: LE(b, c)): LE(a, c) ')
        # le_trans's statement is touched; other.bats mentions LE, not le_trans: nothing selected there
        self.assertEqual(self.select('src/other.bats'), set())
        self.edit('src/m.bats', 'dataprop LE(int, int) =', 'dataprop LE(int, int)  =')
        self.assertEqual(self.select('src/other.bats'), {'uses_le'})

    def test_a_change_of_the_checker_alone_selects_the_smoke_modules_whole(self):
        (self.root / 'tests' / 'static').mkdir(parents=True)
        (self.root / mc.MODULES_FILE).write_text('src/m.bats 2\nsrc/other.bats 1 smoke\n')
        self.git('add', '-A')
        self.git('-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-q', '-m', 'two')
        (self.root / mc.MODULES_FILE).write_text('src/m.bats 2\nsrc/other.bats 1 smoke\n# x\n')
        self.assertIsNone(self.select('src/other.bats'))
        self.assertEqual(self.select('src/m.bats'), set())

    def test_a_proof_and_the_checker_select_both(self):
        (self.root / 'tests' / 'static').mkdir(parents=True)
        (self.root / mc.MODULES_FILE).write_text('src/m.bats 2\nsrc/other.bats 1 smoke\n')
        self.git('add', '-A')
        self.git('-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-q', '-m', 'two')
        (self.root / mc.MODULES_FILE).write_text('src/m.bats 2\nsrc/other.bats 1 smoke\n# x\n')
        self.edit('src/m.bats', 'case+ first of LE_refl() => second', 'case+ first of LE_refl() => (second)')
        self.assertIsNone(self.select('src/other.bats'))
        self.assertEqual(self.select('src/m.bats'), {'le_trans', 'le_twice'})

    def test_the_solver_fixtures_select_everything(self):
        (self.root / 'tests' / 'static' / 'solver' / 'reject').mkdir(parents=True)
        (self.root / 'tests' / 'static' / 'solver' / 'reject' / 'a.dats').write_text('x\n')
        self.git('add', '-A')
        self.git('-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-q', '-m', 'two')
        (self.root / 'tests' / 'static' / 'solver' / 'reject' / 'a.dats').write_text('y\n')
        self.assertIsNone(self.select())

    def test_the_setup_action_pin_selects_everything(self):
        path = self.root / '.github' / 'workflows'
        path.mkdir(parents=True)
        pin = 'uses: bats-lang/bats/.github/actions/setup@'
        (path / 'check.yml').write_text(f'{pin}{"a" * 40}\n')
        self.git('add', '-A')
        self.git('-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-q', '-m', 'two')
        (path / 'check.yml').write_text(f'{pin}{"b" * 40}\n')
        self.assertIsNone(self.select())

    def test_another_line_of_a_workflow_selects_nothing(self):
        path = self.root / '.github' / 'workflows'
        path.mkdir(parents=True)
        (path / 'check.yml').write_text('uses: bats-lang/bats/.github/actions/setup@' + 'a' * 40 + '\nname: one\n')
        self.git('add', '-A')
        self.git('-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-q', '-m', 'two')
        (path / 'check.yml').write_text('uses: bats-lang/bats/.github/actions/setup@' + 'a' * 40 + '\nname: two\n')
        self.assertEqual(self.select(), set())


if __name__ == '__main__':
    unittest.main(verbosity=1)
