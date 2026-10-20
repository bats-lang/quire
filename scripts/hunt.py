#!/usr/bin/env python3
"""The hunt's matrix, its verdicts and its report (quire#575).

The experiment is N independent fresh-runner jobs, each running the start of the
desktop project of a failing group, in `check.yml`'s order, for a few minutes: the
unit of the flake's rate is a fresh job (about 1 in 900), not a page load. Three
arms differ only by the environment of the test run, so the runner, the steps and
the tests are the same:

  full   as CI runs: the stall watch armed, the flight recorder on
  noarm  QUIRE_NO_STALL_ARM=1: no debugger on the pages, the recorder on
  bare   QUIRE_STALL_WATCH=off, QUIRE_NO_RECORDER=1: nothing of ours watches

usage:
  scripts/hunt.py plan                       check the inputs (HUNT_* variables), write
                                             matrix_a, matrix_b, count_a, count_b to $GITHUB_OUTPUT
  scripts/hunt.py classify <arm> <group> <n> <test-results> <timings> <out>
                                             what one job found, as <out>/result.json (and, on
                                             a hit, hit=true to $GITHUB_OUTPUT)
  scripts/hunt.py report <results-dir>       the table of arms, hits and the 95% upper bound of
                                             the rate, to the job summary and standard output

Python because the plan runs before any compiler exists (a matrix needs a range, which a
workflow expression does not have) and the job's verdict reads Playwright's JSON; the
avenue exhausted is bats: the plan job would first have to build the compiler (10 minutes)
for a loop that prints a list (quire#646).
"""
import glob
import json
import math
import os
import re
import sys

ARMS = {
    'full': {},
    'noarm': {'QUIRE_NO_STALL_ARM': '1'},
    'bare': {'QUIRE_STALL_WATCH': 'off', 'QUIRE_NO_RECORDER': '1'},
}
GROUPS = ['relaunch', 'settings', 'extras', 'reader']   # the groups of the four recurrences (#575 rows 1 to 4)
MATRIX_MOST = 256                                        # GitHub's limit of jobs in one matrix
RATE_PER_JOB = 1 / 900                                   # the CI rate the hunt is sized by (#575)


def fail(message):
    print(f'::error::{message}')
    sys.exit(1)


def output(name, value):
    path = os.environ.get('GITHUB_OUTPUT')
    if path:
        with open(path, 'a', encoding='utf-8') as file:
            file.write(f'{name}={value}\n')
    else:
        print(f'{name}={value}')


def plan(env, known_groups=None):
    """The matrix entries of a dispatch, interleaved by arm so a partial run is balanced."""
    arms = env.get('HUNT_ARMS', 'full noarm bare').split()
    groups = env.get('HUNT_GROUPS', ' '.join(GROUPS)).split()
    per_arm = env.get('HUNT_JOBS_PER_ARM', '100')
    seconds = env.get('HUNT_SECONDS', '150')
    if not arms or any(arm not in ARMS for arm in arms) or len(set(arms)) != len(arms):
        fail(f'arms must be some of {" ".join(ARMS)}, each once: {arms}')
    if not groups or (known_groups is not None and any(group not in known_groups for group in groups)):
        fail(f'groups must be e2e groups of tests/groups.json: {groups}')
    if not re.fullmatch(r'[1-9][0-9]{0,2}', per_arm) or int(per_arm) > MATRIX_MOST * 2 // len(arms):
        fail(f'jobs_per_arm must be from 1 to {MATRIX_MOST * 2 // len(arms)} for {len(arms)} arm(s) (two matrices of {MATRIX_MOST}): {per_arm}')
    if not re.fullmatch(r'[1-9][0-9]{1,3}', seconds) or not 30 <= int(seconds) <= 1200:
        fail(f'seconds must be from 30 to 1200: {seconds}')
    entries = []
    for index in range(int(per_arm)):
        for arm in arms:
            entries.append({'arm': arm, 'group': groups[len(entries) % len(groups)], 'n': len(entries) + 1})
    return entries, int(seconds)


def split(entries):
    return entries[:MATRIX_MOST], entries[MATRIX_MOST:]


def e2e_groups(root='.'):
    with open(os.path.join(root, 'tests', 'groups.json'), encoding='utf-8') as file:
        return list(json.load(file)['e2e'])


def walk_tests(suite, found):
    for spec in suite.get('specs', []):
        for test in spec.get('tests', []):
            found.append((spec.get('file', ''), spec.get('title', ''), test))
    for child in suite.get('suites', []):
        walk_tests(child, found)


def playwright_outcomes(timings):
    """(tests that ran and passed, timed-out tests as 'file: title') from the JSON of each run."""
    passed, timed_out = 0, []
    for report in sorted(glob.glob(os.path.join(timings, '*.json'))):
        try:
            with open(report, encoding='utf-8') as file:
                data = json.load(file)
        except (OSError, ValueError):
            continue
        tests = []
        for suite in data.get('suites', []):
            walk_tests(suite, tests)
        for file_name, title, test in tests:
            results = test.get('results', [])
            if any(result.get('status') == 'passed' for result in results):
                passed += 1
            for result in results:
                message = ' '.join(str(error.get('message', '')) for error in result.get('errors', []))
                if result.get('status') == 'timedOut' or 'Test timeout of' in message:
                    timed_out.append(f'{file_name}: {title}')
    return passed, timed_out


def frozen_capture(capture):
    """A capture of a page that answered nothing while its renderers used no CPU: the freeze of #575."""
    if capture.get('presumedBusy'):
        return False
    answers = capture.get('answers') or {}
    silent = (answers.get('task') or {}).get('answered') is False or (capture.get('evaluate') or {}).get('answered') is False
    return silent and ('native' in capture or 'flight' in capture)


def classify(arm, group, n, test_results, timings, out):
    captures, deliberate = [], 0
    for path in sorted(glob.glob(os.path.join(test_results, '**', 'stall-capture-*.json'), recursive=True)):
        # the stall watch's own spec freezes pages on purpose, and its output directories are named for it
        if os.path.basename(os.path.dirname(path)).startswith('stall-capture-'):
            deliberate += 1
            continue
        try:
            with open(path, encoding='utf-8') as file:
                captures.append((path, json.load(file)))
        except (OSError, ValueError):
            captures.append((path, {}))
    passed, timed_out = playwright_outcomes(timings)
    frozen = [path for path, capture in captures if frozen_capture(capture)]
    if frozen:
        verdict = 'hit'
    elif timed_out:
        verdict = 'timeout-without-capture' if arm != 'bare' else 'timeout'
    elif passed == 0:
        verdict = 'broken'
    else:
        verdict = 'clean'
    result = {
        'arm': arm, 'group': group, 'n': n, 'verdict': verdict, 'tests_passed': passed,
        'timed_out': timed_out[:10], 'frozen_captures': frozen, 'captures': len(captures), 'deliberate_captures_ignored': deliberate,
        'image': os.environ.get('ImageVersion', ''), 'runner': os.environ.get('RUNNER_NAME', ''),
    }
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, 'result.json'), 'w', encoding='utf-8') as file:
        json.dump(result, file, indent=1)
    output('verdict', verdict)
    output('hit', 'true' if verdict in ('hit', 'timeout-without-capture', 'timeout') else 'false')
    return result


def upper_bound(hits, n, confidence=0.95):
    """The one-sided upper bound of a rate seen `hits` times in `n` jobs (Clopper-Pearson, by bisection)."""
    if n == 0:
        return 1.0
    if hits == 0:
        return 1 - (1 - confidence) ** (1 / n)

    def cdf(p):   # P(X <= hits) for X ~ Binomial(n, p)
        return sum(math.comb(n, k) * p ** k * (1 - p) ** (n - k) for k in range(hits + 1))
    low, high = hits / n, 1.0
    for _ in range(80):
        middle = (low + high) / 2
        if cdf(middle) > 1 - confidence:
            low = middle
        else:
            high = middle
    return high


def report(results_dir):
    results = []
    for path in sorted(glob.glob(os.path.join(results_dir, '**', 'result.json'), recursive=True)):
        with open(path, encoding='utf-8') as file:
            results.append(json.load(file))
    lines = ['## Hunt report (quire#575)', '', f'{len(results)} job result(s). The CI rate being hunted is about 1 in {round(1 / RATE_PER_JOB)} fresh jobs.', '',
             '| arm | jobs counted | hits | timeouts without a capture | broken (not counted) | 95% upper bound of the rate | chance this N saw a 1-in-900 event |',
             '|---|---|---|---|---|---|---|']
    hit_lines = []
    for arm in ARMS:
        mine = [result for result in results if result['arm'] == arm]
        if not mine:
            continue
        broken = [result for result in mine if result['verdict'] == 'broken']
        counted = len(mine) - len(broken)
        hits = [result for result in mine if result['verdict'] == 'hit']
        timeouts = [result for result in mine if result['verdict'] in ('timeout-without-capture', 'timeout')]
        events = len(hits) + len(timeouts)
        bound = upper_bound(events, counted)
        power = 1 - (1 - RATE_PER_JOB) ** counted
        lines.append(f'| {arm} | {counted} | {len(hits)} | {len(timeouts)} | {len(broken)} | 1 in {round(1 / bound) if bound else "inf"} ({bound:.4%}) | {power:.0%} |')
        for result in hits + timeouts:
            hit_lines.append(f'- {arm} #{result["n"]} ({result["group"]}): {result["verdict"]}, {result["tests_passed"]} tests passed first; timed out: {"; ".join(result["timed_out"]) or "none"}; captures: {", ".join(result["frozen_captures"]) or "none"}')
    lines += ['', 'The bound is for hits plus timeouts together: zero events in N jobs gives a rate under 1 - 0.05^(1/N) with 95% confidence. A jobs-per-arm that leaves the last column under 95% cannot rule a 1-in-900 event out.', '']
    if hit_lines:
        lines += ['### Events', ''] + hit_lines + ['', 'Artifacts `hunt-hit-<arm>-<n>` hold the stall capture, the flight recorder\'s kernel ring and Chrome trace, and the traces.']
    else:
        lines += ['No hit in this dispatch.']
    text = '\n'.join(lines)
    print(text)
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a', encoding='utf-8') as file:
            file.write(text + '\n')
    return results


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    command = argv[1]
    if command == 'plan':
        entries, seconds = plan(os.environ, e2e_groups())
        first, second = split(entries)
        output('matrix_a', json.dumps({'include': first}))
        output('matrix_b', json.dumps({'include': second or [{'arm': 'none', 'group': 'none', 'n': 0}]}))
        output('count_a', len(first))
        output('count_b', len(second))
        output('seconds', seconds)
        print(f'{len(entries)} jobs: {len(first)} + {len(second)}; {seconds} s of tests in each')
    elif command == 'classify':
        arm, group, n, test_results, timings, out = argv[2:8]
        print(json.dumps(classify(arm, group, int(n), test_results, timings, out)))
    elif command == 'report':
        report(argv[2])
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
