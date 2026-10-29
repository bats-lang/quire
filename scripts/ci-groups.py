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
  scripts/ci-groups.py local [<base>]  the static fixtures the working tree's change since the git
                                       revision <base> (default origin/main) can affect, one
                                       `accept/<name>` or `reject/<name>` a line, as
                                       `bats fixtures tests/static --list-affected <paths>` lists
                                       them (bats#570): a worker runs those with
                                       tests/static/run.sh, not the whole population (#1006). Needs
                                       BATS_REPOSITORY and bats on PATH; the work directory is
                                       $QUIRE_STATIC_WORK (the one run.sh uses), else
                                       ~/.cache/quire-static
  scripts/ci-groups.py members <kind> <group>
                                       check, then print that group's
                                       members, one per line (e2e specs
                                       as paths from the checkout's root)
"""
import json
import os
import re
import subprocess
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


def changed_paths(base, run=subprocess.run):
    """The paths the working tree differs in from <base>, committed or not (a deleted path
    included, which names what a fixture read), and the untracked ones git does not ignore.
    Stopgap (keyword: list-affected): bats#582 gives `bats fixtures --changed-since <rev>`, and
    this function and its tests are deleted when quire calls that."""
    paths = []
    for command in (['git', 'diff', '--name-only', base], ['git', 'ls-files', '--others', '--exclude-standard']):
        done = run(command, cwd=ROOT, capture_output=True, text=True)
        if done.returncode != 0:
            raise RuntimeError(f"{' '.join(command)} failed: {done.stderr.strip()}")
        paths += [line for line in done.stdout.splitlines() if line and line not in paths]
    return paths


def local_affected(base, environment, run=subprocess.run):
    """The command line and the paths of `local`: `bats fixtures tests/static --list-affected`
    over the paths changed since <base>, with the memo that tests/static/run.sh keeps."""
    repository = environment.get('BATS_REPOSITORY')
    if not repository:
        raise RuntimeError('BATS_REPOSITORY (the package repository) is not set')
    work = environment.get('QUIRE_STATIC_WORK') or os.path.join(
        environment.get('XDG_CACHE_HOME') or os.path.join(os.path.expanduser('~'), '.cache'), 'quire-static')
    paths = changed_paths(base, run)
    if not paths:
        return None
    return (['bats', 'fixtures', 'tests/static', '--work', work, '--memo', os.path.join(work, 'memo'),
             '--repository', repository, '--list-affected'] + paths, paths)


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
    if arguments[:1] == ['local'] and len(arguments) in (1, 2):
        try:
            found = local_affected(arguments[1] if len(arguments) == 2 else 'origin/main', os.environ)
        except RuntimeError as error:
            print(f'error: {error}', file=sys.stderr)
            return 1
        if found is None:
            print('no change since the base: no fixture is affected', file=sys.stderr)
            return 0
        command, paths = found
        print(f'{len(paths)} changed paths; {" ".join(command[:3])} --list-affected:', file=sys.stderr)
        return subprocess.run(command, cwd=ROOT).returncode
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
