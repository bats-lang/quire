#!/usr/bin/env python3
"""scripts/hunt.py (quire#575): the plan's checks, the verdict of a job, the bound of a rate."""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'scripts'))
import hunt  # noqa: E402


def quietly(function, *args):
    with contextlib.redirect_stdout(io.StringIO()):
        return function(*args)


class Plan(unittest.TestCase):
    def test_default_is_300_jobs_in_two_matrices_balanced_by_arm(self):
        entries, seconds = hunt.plan({}, hunt.e2e_groups(ROOT))
        self.assertEqual(len(entries), 300)
        self.assertEqual(seconds, 150)
        first, second = hunt.split(entries)
        self.assertEqual((len(first), len(second)), (256, 44))
        for arm in hunt.ARMS:
            self.assertEqual(sum(1 for entry in entries if entry['arm'] == arm), 100)
        # the groups of the four recurrences are dealt evenly inside each arm
        for arm in hunt.ARMS:
            groups = [entry['group'] for entry in entries if entry['arm'] == arm]
            self.assertEqual({group: groups.count(group) for group in hunt.GROUPS}, {group: 25 for group in hunt.GROUPS})
        self.assertEqual([entry['n'] for entry in entries], list(range(1, 301)))

    def test_bad_inputs_are_refused(self):
        groups = hunt.e2e_groups(ROOT)
        for bad in [{'HUNT_ARMS': ''}, {'HUNT_ARMS': 'full full'}, {'HUNT_ARMS': 'loud'}, {'HUNT_GROUPS': 'nosuch'},
                    {'HUNT_GROUPS': ''}, {'HUNT_JOBS_PER_ARM': '0'}, {'HUNT_JOBS_PER_ARM': '171'}, {'HUNT_JOBS_PER_ARM': '-1'},
                    {'HUNT_JOBS_PER_ARM': '1e2'}, {'HUNT_SECONDS': '29'}, {'HUNT_SECONDS': '1201'}, {'HUNT_SECONDS': 'x'}]:
            with self.subTest(bad), self.assertRaises(SystemExit):
                quietly(hunt.plan, bad, groups)

    def test_one_arm_may_take_the_whole_budget(self):
        entries, _ = hunt.plan({'HUNT_ARMS': 'full', 'HUNT_JOBS_PER_ARM': '512'}, hunt.e2e_groups(ROOT))
        self.assertEqual(len(entries), 512)
        with self.assertRaises(SystemExit):
            quietly(hunt.plan, {'HUNT_ARMS': 'full', 'HUNT_JOBS_PER_ARM': '513'}, hunt.e2e_groups(ROOT))

    def test_the_groups_of_the_recurrences_exist(self):
        self.assertTrue(set(hunt.GROUPS) <= set(hunt.e2e_groups(ROOT)))


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as file:
        json.dump(data, file)


def playwright_report(statuses):
    return {'suites': [{'specs': [{'file': 'dictionary.spec.js', 'title': f'test {i}', 'tests': [{'results': [{'status': status, 'errors': (
        [{'message': 'Test timeout of 90000ms exceeded.'}] if status == 'timedOut' else [])}]}]} for i, status in enumerate(statuses)]}]}


FROZEN = {'presumedBusy': None, 'answers': {'task': {'answered': False}}, 'native': {}, 'flight': {}}


class Classify(unittest.TestCase):
    def verdict(self, arm, statuses, captures):
        with tempfile.TemporaryDirectory() as tmp:
            results, timings, out = (os.path.join(tmp, name) for name in ('test-results', 'timings', 'out'))
            write(os.path.join(timings, 'parallel.json'), playwright_report(statuses))
            for directory, capture in captures.items():
                write(os.path.join(results, 'parallel', directory, 'stall-capture-1.json'), capture)
            return quietly(hunt.classify, arm, 'settings', 7, results, timings, out)

    def test_clean_job(self):
        self.assertEqual(self.verdict('full', ['passed'] * 30, {})['verdict'], 'clean')

    def test_a_job_that_ran_no_test_is_broken_and_not_counted(self):
        self.assertEqual(self.verdict('full', [], {})['verdict'], 'broken')

    def test_a_frozen_capture_is_a_hit(self):
        result = self.verdict('full', ['passed'] * 24 + ['timedOut'], {'dictionary-x-desktop': FROZEN})
        self.assertEqual(result['verdict'], 'hit')
        self.assertEqual(result['tests_passed'], 24)
        self.assertEqual(len(result['frozen_captures']), 1)

    def test_a_busy_page_is_not_a_hit_but_its_timeout_is_seen(self):
        busy = dict(FROZEN, presumedBusy='renderer 1 used 1 s')
        self.assertEqual(self.verdict('full', ['passed'] * 3 + ['timedOut'], {'a-desktop': busy})['verdict'], 'timeout-without-capture')

    def test_the_watch_specs_own_deliberate_freezes_are_ignored(self):
        result = self.verdict('full', ['passed'] * 5, {'stall-capture-a-frozen-renderer-desktop': FROZEN})
        self.assertEqual(result['verdict'], 'clean')
        self.assertEqual(result['deliberate_captures_ignored'], 1)

    def test_a_timeout_in_the_bare_arm_is_a_timeout_with_nothing_to_read(self):
        self.assertEqual(self.verdict('bare', ['passed'] * 3 + ['timedOut'], {})['verdict'], 'timeout')


class Bound(unittest.TestCase):
    def test_no_hit_in_n_is_the_rule_of_three(self):
        self.assertAlmostEqual(hunt.upper_bound(0, 100), 1 - 0.05 ** (1 / 100))
        self.assertAlmostEqual(hunt.upper_bound(0, 900) * 900, 3.0, delta=0.1)

    def test_one_hit_in_100_is_the_textbook_bound(self):
        # Clopper-Pearson one-sided 95%: 4.66% for 1 in 100
        self.assertAlmostEqual(hunt.upper_bound(1, 100), 0.0466, places=3)

    def test_the_report_counts_hits_per_arm_and_leaves_broken_jobs_out(self):
        with tempfile.TemporaryDirectory() as tmp:
            for n, (arm, verdict) in enumerate([('full', 'clean'), ('full', 'hit'), ('full', 'broken'), ('bare', 'clean')]):
                write(os.path.join(tmp, f'hunt-result-{arm}-{n}', 'result.json'), {
                    'arm': arm, 'group': 'settings', 'n': n, 'verdict': verdict, 'tests_passed': 5, 'timed_out': [], 'frozen_captures': []})
            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                hunt.report(tmp)
            text = buffer.getvalue()
            self.assertIn('| full | 2 | 1 | 0 | 1 |', text)
            self.assertIn('| bare | 1 | 0 | 0 | 0 |', text)
            self.assertIn('### Events', text)


if __name__ == '__main__':
    unittest.main(verbosity=1)
