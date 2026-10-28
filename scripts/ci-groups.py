#!/usr/bin/env python3
"""The groups CI runs the tests in, side by side (tests/groups.json).

Two kinds of group:

* e2e: each a list of the specs under e2e/ one job runs, by area
  (library and import; the reader and its page turns; the reading tools;
  sync, backup, catalogues, settings and the rest);
* static: each a list of what one job of the static tests runs: `check`
  (bats check of the app itself), `checkers` (ids.py and case_plus.py,
  with their fixtures), and the fixtures, `accept/<name>` and
  `reject/<name>` under tests/static/. Every job that runs a fixture
  checks the app first (the long part: 9 min on CI), and each fixture
  then checks only its module again: on CI about 13 s for a reject, 54 s
  for an accept (which links the app). A fixture about the stylesheet is
  put in the module of its area (src/palette.bats for the roles), not in
  one that holds the proofs, which are the slowest to check (src/style.bats
  once held all of them: 7 min for one fixture). So a group is the app's
  check and as many fixtures as keep it near the e2e path (build, 10.5
  min, then a group of e2e, 5): `app` (with `check`) takes the rejects,
  `accepts` the accepts and a few rejects. The split into groups of about
  equal time is measured (keyword: static groups, #618).

Every spec and every static member is in exactly one group of its kind,
and every name a group lists exists: anything else fails, so a spec or a
fixture added and not put in a group fails CI instead of never running.

Every e2e group runs in the `android` project too (#295): every project
of playwright.config.js runs in each group (check.yml's run, through
`gen-pwa test`, names no --project), and the `android` project must be
there and run every spec: no testMatch, testIgnore, grep or grepInvert
in it or over the whole configuration, and no --project, --grep or
--grep-invert on the run (`gen-pwa test`'s own split by @serial runs
every test, in one of its two runs). A
spec that cannot apply on Android skips itself, saying why. Removing the
project or narrowing it fails CI.

usage:
  scripts/ci-groups.py matrix          check, then write e2e=[...] and
                                       static=[...] (the matrices' group
                                       names, as JSON) to $GITHUB_OUTPUT,
                                       or to standard output
  scripts/ci-groups.py plan <base> [full]
                                       what every group runs for a change since the git
                                       revision <base> (`none`: no change to go by, a push,
                                       a dispatch, the nightly run: every group; `full`: the
                                       merge group, whose e2e and static groups run whole
                                       and whose mutation groups still compare with <base>):
                                       the outputs e2e_run and static_run (JSON) to
                                       $GITHUB_OUTPUT, or to standard output, and the reason
                                       of each path to $GITHUB_STEP_SUMMARY (#619)
  scripts/ci-groups.py affected <group> <base>
                                       print `yes` when the group has something to run for
                                       the same change, else `no`: the groups of mutation
                                       members run only the lemmas the change can have made
                                       vacuous (#594), the others what scripts/affected.py
                                       selects
  scripts/ci-groups.py local <base> [--sample N [--seed S]] [--run <repository>]
                                       a worker's local run for the change since <base> (the
                                       merge base with origin/main, tracked files of the
                                       working tree included), by the rule CI uses at the
                                       granularity of a fixture (keyword: affected): the
                                       members to run, one per line (`check`, `checkers`,
                                       every fixture that reads a changed file, every e2e spec
                                       the rule selects as e2e/<spec>: all of them for a change
                                       under src/**), the reasons on standard error. A path for which CI runs the whole static
                                       population is said, and --sample N adds N fixtures drawn
                                       with the seed S (printed). --run runs the static
                                       members with tests/static/run.sh (bats on PATH), then
                                       the specs with `dist/debug/gen-pwa test -- <specs>` (built as
                                       in .claude/rules/ci.md; run it under the env file).
                                       Stopgap (keyword: affected): the fixture list is derived from
                                       the source; bats-lang/bats#570 gives it from the fixtures memo,
                                       and the derivation is deleted when it lands
  scripts/ci-groups.py members <kind> <group>
                                       check, then print that group's
                                       members, one per line (e2e specs
                                       as paths from the checkout's root)
"""
import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import affected as selection  # noqa: E402  (which specs and members a change can affect, #619)


def specs():
    """Every spec of the e2e suite, by file name."""
    return sorted(name for name in os.listdir(os.path.join(ROOT, 'e2e'))
                  if name.endswith('.spec.js'))


def mutation_members():
    """The mutation members: mutation/<module>, or mutation/<module>-part<i>of<n> for a module
    split in n parts (tests/static/mutation_modules.txt)."""
    sys.path.insert(0, os.path.join(ROOT, 'tests', 'static'))
    import mutation_check
    return [mutation_check.member_name(file, shards, index)
            for file, shards, _ in mutation_check.read_modules(ROOT) for index in range(1, shards + 1)]


def static_members():
    """Everything the static tests run: the app's check, the checkers,
    and each fixture."""
    found = ['check', 'checkers', 'solver'] + mutation_members()
    for verdict in ('accept', 'reject'):
        directory = os.path.join(ROOT, 'tests', 'static', verdict)
        found += sorted(f'{verdict}/{name}' for name in os.listdir(directory)
                        if os.path.isdir(os.path.join(directory, name)))
    return found


NARROWING = ('testMatch', 'testIgnore', 'grep', 'grepInvert')


def project_blocks(config):
    """Each project of the configuration's `projects` list: its name and
    its text, from the `{` that opens it to the `}` that closes it."""
    start = config.find('projects:')
    if start < 0:
        return []
    blocks, depth, opened = [], 0, None
    position = config.index('[', start) + 1
    while position < len(config):
        character = config[position]
        if character == '/' and config.startswith('//', position):
            position = config.index('\n', position)
            continue
        if character in '\'"`':
            end = position + 1
            while config[end] != character:
                end += 2 if config[end] == '\\' else 1
            position = end + 1
            continue
        if character in '{[(':
            if depth == 0 and character == '{':
                opened = position
            depth += 1
        elif character in '}])':
            if depth == 0:
                break
            depth -= 1
            if depth == 0 and character == '}':
                text = config[opened:position + 1]
                name = re.search(r"name:\s*'([^']*)'", text)
                blocks.append((name.group(1) if name else '', text))
        position += 1
    return blocks


def without_comments(text):
    """The text with its line comments dropped (a comment may name a key)."""
    return re.sub(r'(^|\s)//[^\n]*', r'\1', text)


def android_problems():
    """What keeps the `android` project from running every spec in every
    e2e group."""
    found = []
    with open(os.path.join(ROOT, 'playwright.config.js')) as config_file:
        config = config_file.read()
    blocks = dict(project_blocks(config))
    if 'android' not in blocks:
        found.append('playwright.config.js has no `android` project: every spec runs on Android (#295)')
    else:
        for key in NARROWING:
            if re.search(rf'\b{key}\s*:', without_comments(blocks['android'])):
                found.append(f'the `android` project is narrowed by {key}: it runs every spec (#295)')
    outside = without_comments(config[:config.find('projects:')])
    for key in NARROWING:
        if re.search(rf'\b{key}\s*:', outside):
            found.append(f'playwright.config.js narrows every project by {key}, android among them (#295)')
    with open(os.path.join(ROOT, '.github', 'workflows', 'check.yml')) as workflow_file:
        runs = [line for line in workflow_file if 'playwright test' in line or 'gen-pwa test' in line]
    if not any('gen-pwa test' in line for line in runs):
        found.append('check.yml runs no `gen-pwa test`')
    for line in runs:
        if re.search(r'--project|--grep|(^|\s)-g\s', line):
            found.append(f'check.yml narrows the e2e run, so a group may leave out the `android` project: {line.strip()}')
    return found


def problems(groups):
    """What is wrong with the groups: each name not in exactly one group
    of its kind, or not one that exists."""
    found = []
    for kind, expected in (('e2e', specs()), ('static', static_members())):
        listed = {}
        for group, members in groups[kind].items():
            if not members:
                found.append(f'{kind} group {group} is empty')
            for member in members:
                listed.setdefault(member, []).append(group)
        for member in expected:
            where = listed.pop(member, [])
            if not where:
                found.append(f'{kind}: {member} is in no group (add it to one in tests/groups.json)')
            elif len(where) > 1:
                found.append(f'{kind}: {member} is in more than one group: {", ".join(where)}')
        for member, where in sorted(listed.items()):
            found.append(f'{kind}: {member} (in {", ".join(where)}) does not exist')
    for group in sorted(set(groups['e2e']) & set(groups['static'])):
        found.append(f'{group} is the name of an e2e group and of a static one (tests/groups.json)')
    return found


def affected(members, base):
    """`yes` when a change since `base` leaves something for these members to run."""
    if not all(member.startswith('mutation/') for member in members):
        return 'yes'
    if base == 'none':
        return 'no'  # a push, a dispatch: the scheduled run (.github/workflows/mutation.yml) has them
    sys.path.insert(0, os.path.join(ROOT, 'tests', 'static'))
    import mutation_check
    for member in members:
        file, index, count = mutation_check.parse_member(ROOT, member)
        original = open(os.path.join(ROOT, file)).read().split('\n')
        if mutation_check.selected_names(ROOT, file, original, set(), base, (index, count)):
            return 'yes'
    return 'no'


def plan(groups, base, full=False):
    """What every group runs for a change since `base` (scripts/affected.py); `full`
    runs every e2e and static group whole, the mutation groups by their own rule."""
    changes = None if base == 'none' or full else selection.git_changes(base, ROOT)
    return selection.plan(groups, changes, selection.Tree(ROOT),
                          lambda members: affected(members, base) == 'yes')


def group_affected(groups, group, base):
    """`yes` or `no` for one group of either kind."""
    result = plan(groups, base)
    if group in result['e2e']:
        return 'yes' if result['e2e'][group] else 'no'
    return 'yes' if result['static'][group]['members'] else 'no'


def local(groups, arguments):
    """The `local` command: print (and with --run, run) a change's members. Returns the status."""
    import random
    import subprocess
    base, options = arguments[0], arguments[1:]
    sample, seed, repository = 0, None, None
    while options:
        if options[0] == '--sample' and len(options) > 1 and options[1].isdigit():
            sample, options = int(options[1]), options[2:]
        elif options[0] == '--seed' and len(options) > 1 and options[1].isdigit():
            seed, options = int(options[1]), options[2:]
        elif options[0] == '--run' and len(options) > 1:
            repository, options = options[1], options[2:]
        else:
            return None
    changes = selection.git_changes(base, ROOT, head=None)
    result = selection.local_plan(changes, selection.Tree(ROOT))
    members = list(result['static'])
    for line in result['why']:
        print(line, file=sys.stderr)
    if result['whole']:
        print('CI runs the whole static population for: ' + '; '.join(result['whole']), file=sys.stderr)
    if sample:
        seed = random.SystemRandom().randrange(10**9) if seed is None else seed
        pool = [member for member in selection.fixture_members(selection.Tree(ROOT)) if member not in members]
        drawn = random.Random(seed).sample(pool, min(sample, len(pool)))
        print(f'seeded sample: {len(drawn)} of {len(pool)} other fixtures, seed {seed}', file=sys.stderr)
        members += sorted(drawn)
    if result['e2e'] == selection.ALL:
        print('e2e: every spec (the app or a shared module changed; a spec reads the built app)', file=sys.stderr)
        specs_list = [f'e2e/{name}' for name in specs()]
    else:
        specs_list = sorted(result['e2e'])
    print('\n'.join(members + specs_list))
    if repository is None:
        return 0
    status = 0
    if members:
        status = subprocess.run([os.path.join(ROOT, 'tests', 'static', 'run.sh'), repository] + members).returncode
    if specs_list:
        # as CI's e2e job does (check.yml, "Run e2e tests"): the generator serves dist/pwa and runs the specs
        try:
            status = subprocess.run([os.path.join(ROOT, 'dist', 'debug', 'gen-pwa'), 'test', '--'] + specs_list,
                                    cwd=ROOT).returncode or status
        except FileNotFoundError:
            print('dist/debug/gen-pwa is not built: the e2e steps of .claude/rules/ci.md, "Checking locally", come first', file=sys.stderr)
            return 2
    return status


def main(arguments):
    with open(os.path.join(ROOT, 'tests', 'groups.json')) as groups_file:
        groups = json.load(groups_file)
    found = problems(groups) + android_problems()
    if found:
        for problem in found:
            print(f'::error file=tests/groups.json::{problem}')
        return 1
    if arguments == ['matrix']:
        lines = [f'{kind}={json.dumps(sorted(groups[kind]))}' for kind in ('e2e', 'static')]
        output = os.environ.get('GITHUB_OUTPUT')
        if output:
            with open(output, 'a') as output_file:
                output_file.write(''.join(line + '\n' for line in lines))
        print('\n'.join(lines))
        total = len(specs()), len(static_members())
        print(f'{total[0]} specs and {total[1]} static members, each in exactly one group',
              file=sys.stderr)
        return 0
    if arguments[:1] == ['plan'] and len(arguments) in (2, 3) and arguments[2:] in ([], ['full']):
        result = plan(groups, arguments[1], full=len(arguments) == 3)
        lines = [f"e2e_run={json.dumps(result['e2e'], separators=(',', ':'))}",
                 f"static_run={json.dumps(result['static'], separators=(',', ':'))}"]
        output = os.environ.get('GITHUB_OUTPUT')
        if output:
            with open(output, 'a') as output_file:
                output_file.write(''.join(line + '\n' for line in lines))
        report = [f'## What this run has to run (base: {arguments[1]})', '']
        report += [f'* {line}' for line in result['why']] + ['']
        report += ['e2e groups run: ' + (', '.join(group for group, run in result['e2e'].items() if run) or 'none')]
        for group, info in result['static'].items():
            members = info['members'].split()
            report.append(f'static {group}: ' + ('nothing' if not members else
                          f'{len(members)} of {len(groups["static"][group])} members' + (f' ({info["members"]})' if len(members) <= 6 else '')))
        summary = os.environ.get('GITHUB_STEP_SUMMARY')
        if summary:
            with open(summary, 'a') as summary_file:
                summary_file.write('\n'.join(report) + '\n')
        print('\n'.join(lines + report))
        return 0
    if arguments[:1] == ['local'] and len(arguments) >= 2:
        status = local(groups, arguments[1:])
        if status is not None:
            return status
    if len(arguments) == 3 and arguments[0] == 'affected' \
            and (arguments[1] in groups['static'] or arguments[1] in groups['e2e']):
        print(group_affected(groups, arguments[1], arguments[2]))
        return 0
    if len(arguments) == 3 and arguments[0] == 'members' and arguments[1] in groups \
            and arguments[2] in groups[arguments[1]]:
        kind, group = arguments[1], arguments[2]
        prefix = 'e2e/' if kind == 'e2e' else ''
        print('\n'.join(prefix + member for member in groups[kind][group]))
        return 0
    print(__doc__.split('usage:')[1], file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
