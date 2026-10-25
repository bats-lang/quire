#!/usr/bin/env python3
"""The verdicts of proofs_audit.py (quire#840, #841), on lemmas whose rows are known.

`--fail-on high` passes only when every HIGH row has a verdict whose fixtures exist; a row injected
into a copy of the sources, with no verdict, fails it; a verdict that names a fixture which is not
there fails it; a prval in the body of a function does not make the lines after it proof.

usage: tests/static/proofs_audit_test.py
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
AUDIT = HERE / 'proofs_audit.py'
SOLVER_REJECT = HERE / 'solver' / 'reject'


def run(*arguments):
    done = subprocess.run([sys.executable, '-B', '-I', str(AUDIT), *arguments], capture_output=True, text=True)
    return done.returncode, done.stdout + done.stderr


LEMMA = '''prfun xor_pair {left,right:nat} .<left+right>. (): [joined:nat] XOR(left, right, joined) =
  sif left == 0 then XOR_nil()
  else (sif left == 2*(left/2) then xor_double(xor_pair{left/2,right/2}()) else XOR_11(xor_pair{left/2,right/2}()))
'''


class Verdicts(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'src').mkdir()

    def write(self, name, text):
        path = self.root / name
        path.write_text(text)
        return str(path)

    def test_a_row_without_a_verdict_fails(self):
        self.write('src/lemma.bats', LEMMA)
        verdicts = self.write('verdicts.txt', '# none\n')
        code, out = run('--fail-on', 'high', '--verdicts', verdicts, str(self.root / 'src'))
        self.assertEqual(code, 1, out)
        self.assertIn('NO VERDICT: quire | src/lemma.bats | xor_pair | nested', out)

    def test_a_row_with_a_verdict_passes(self):
        self.write('src/lemma.bats', LEMMA)
        fixture = sorted(SOLVER_REJECT.glob('*.dats'))[0].stem
        verdicts = self.write('verdicts.txt', f'quire | src/lemma.bats | xor_pair | nested | {fixture} | a probe\n')
        code, out = run('--fail-on', 'high', '--verdicts', verdicts, str(self.root / 'src'))
        self.assertEqual(code, 0, out)
        self.assertIn(f'=> verdict: {fixture}', out)

    def test_a_verdict_for_a_fixture_that_is_not_there_fails(self):
        self.write('src/lemma.bats', LEMMA)
        verdicts = self.write('verdicts.txt', 'quire | src/lemma.bats | xor_pair | nested | no-such-fixture | a probe\n')
        code, out = run('--fail-on', 'high', '--verdicts', verdicts, str(self.root / 'src'))
        self.assertEqual(code, 1, out)
        self.assertIn('BAD VERDICT', out)
        self.assertIn('no-such-fixture.dats is not in tests/static/solver/reject/', out)

    def test_a_malformed_verdict_fails(self):
        self.write('src/lemma.bats', LEMMA)
        verdicts = self.write('verdicts.txt', 'quire | src/lemma.bats | xor_pair | nested\n')
        code, out = run('--fail-on', 'high', '--verdicts', verdicts, str(self.root / 'src'))
        self.assertEqual(code, 1, out)
        self.assertIn('not `scope | file | proof | kind | fixtures | reason`', out)

    def test_a_prval_in_a_function_does_not_make_its_arithmetic_a_proof(self):
        self.write('src/pinch.bats', '''implement pinch (evs) = let
  prval () = fold@(c)
in
  list_vt_cons(GPinch(region, d * scale_one() / d0, x1 + (x2 - x1) / 2), evs)
end
''')
        verdicts = self.write('verdicts.txt', '# none\n')
        code, out = run('--fail-on', 'high', '--verdicts', verdicts, str(self.root / 'src'))
        self.assertEqual(code, 0, out)
        self.assertIn('0 high', out)

    def test_the_lines_of_a_proof_are_still_rows(self):
        self.write('src/proof.bats', '''implement pinch (evs) = let
  prval first = rotr_digits_2{h/4, l/4, h - 4*(h/4), l - 4*(l/4)}()
in evs end
''')
        verdicts = self.write('verdicts.txt', '# none\n')
        code, out = run('--fail-on', 'high', '--verdicts', verdicts, str(self.root / 'src'))
        self.assertEqual(code, 1, out)
        self.assertIn('NO VERDICT: quire | src/proof.bats | pinch | nested', out)


if __name__ == '__main__':
    unittest.main(argv=[sys.argv[0]], verbosity=1)
