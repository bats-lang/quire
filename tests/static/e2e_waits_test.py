#!/usr/bin/env python3
"""Tests of tests/static/e2e_waits.py (quire#976): each class it covers has a case that fails when the
class occurs (the injection), and the clean cases pass. No bats, no network.

usage: python3 tests/static/e2e_waits_test.py
"""
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import e2e_waits as ew  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))


def tree(files, allowed=''):
    """A scratch root holding e2e/<name>: text and the allowance list."""
    root = tempfile.mkdtemp()
    for name, text in files.items():
        path = os.path.join(root, 'e2e', name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8') as handle:
            handle.write(text)
    os.makedirs(os.path.join(root, 'tests', 'static'))
    with open(os.path.join(root, ew.ALLOWED), 'w', encoding='utf-8') as handle:
        handle.write(allowed)
    return root


def findings(files, allowed=''):
    return ew.lint(tree(files, allowed))[0]


class FixedWaits(unittest.TestCase):
    def test_the_repository_is_clean(self):
        found, total, _ = ew.lint(ROOT)
        self.assertEqual(found, [])
        self.assertEqual(total, 0, 'quire#985 migrated every wait: the allowance list holds none')

    def test_injected_wait_for_timeout_is_refused(self):
        found = findings({'a.spec.js': "await page.waitForTimeout(45000);\n"})
        self.assertEqual(len(found), 1)
        self.assertIn('a.spec.js:1: a fixed wait', found[0])

    def test_injected_sleeps_are_refused(self):
        for line in ("await new Promise((r) => setTimeout(r, t));", "await new Promise((resolve) => setTimeout(resolve, 500));",
                     "await new Promise((resolve) => setTimeout(() => resolve(), 500));", "setTimeout(done , 10);"):
            with self.subTest(line=line):
                self.assertEqual(len(findings({'a.spec.js': line + '\n'})), 1)

    def test_a_budget_a_limit_and_a_comment_are_not_waits(self):
        text = ("test.setTimeout(300000);\n"
                "const timer = setTimeout(() => resolve({ answered: false }), ms);\n"
                "await startLoop(page, `setTimeout(() => spin(), 0)`);\n"
                "await startLoop(page, 'setTimeout(spinForever, 0)');\n"
                "// await page.waitForTimeout(500) was here\n"
                " * a sleep, setTimeout(resolve, 5), is refused\n")
        self.assertEqual(findings({'a.spec.js': text}), [])

    def test_a_listed_wait_passes_and_a_new_one_in_the_file_fails(self):
        allowed = 'e2e/a.spec.js\t1\t#985\n'
        self.assertEqual(findings({'a.spec.js': "await page.waitForTimeout(1);\n"}, allowed), [])
        found = findings({'a.spec.js': "await page.waitForTimeout(1);\nawait page.waitForTimeout(2);\n"}, allowed)
        self.assertEqual(len(found), 1)
        self.assertIn('a.spec.js:2:', found[0])

    def test_a_migrated_wait_lowers_the_count(self):
        found = findings({'a.spec.js': "await page.waitForTimeout(1);\n"}, 'e2e/a.spec.js\t2\t#985\n')
        self.assertEqual(len(found), 1)
        self.assertIn('lower the count to 1', found[0])

    def test_an_entry_names_its_ticket_and_a_file_of_e2e(self):
        self.assertTrue(findings({'a.spec.js': 'x\n'}, 'e2e/a.spec.js\t1\n'))
        self.assertTrue(findings({'a.spec.js': 'x\n'}, 'e2e/a.spec.js\t1\tsoon\n'))
        self.assertTrue(findings({'a.spec.js': 'x\n'}, 'e2e/gone.spec.js\t1\t#985\n'))

    def test_the_wait_is_found_in_a_nested_directory(self):
        self.assertEqual(len(findings({'nested/b.case.js': "await page.waitForTimeout(1);\n"})), 1)


class Quarantine(unittest.TestCase):
    def test_a_mark_with_its_ticket_passes(self):
        for line in ("test.fixme('#807 the gdb teardown', async ({ page }) => {});",
                     "  test.fixme(true, '#891 the ring lock');"):
            with self.subTest(line=line):
                self.assertEqual(findings({'a.spec.js': line + '\n'}), [])

    def test_injected_mark_without_a_ticket_is_refused(self):
        found = findings({'a.spec.js': "test.fixme('the gdb teardown', async () => {});\n"})
        self.assertEqual(len(found), 1)
        self.assertIn('names its ticket', found[0])

    def test_injected_mark_on_one_project_is_refused(self):
        self.assertEqual(len(findings({'a.spec.js': "test.fixme(testInfo.project.name === 'desktop', '#807 teardown');\n"})), 1)


if __name__ == '__main__':
    unittest.main()
