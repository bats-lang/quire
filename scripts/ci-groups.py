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
  for an accept (which links the app), 7 min for one in style.bats,
  whose proofs are the slowest to check. So a group is the app's check
  and as many fixtures as keep it near the e2e path (build, 10.5 min,
  then a group of e2e, 5): `app` (with `check`) takes the rejects,
  `accepts` the accepts and a few rejects, `style` the style.bats one.

Every spec and every static member is in exactly one group of its kind,
and every name a group lists exists: anything else fails, so a spec or a
fixture added and not put in a group fails CI instead of never running.

Every e2e group runs in the `android` project too (#295): every project
of playwright.config.js runs in each group (check.yml's run names no
--project), and the `android` project must be there and run every spec:
no testMatch, testIgnore, grep or grepInvert in it or over the whole
configuration, and no --project, --grep or --grep-invert on the run. A
spec that cannot apply on Android skips itself, saying why. Removing the
project or narrowing it fails CI.

usage:
  scripts/ci-groups.py matrix          check, then write e2e=[...] and
                                       static=[...] (the matrices' group
                                       names, as JSON) to $GITHUB_OUTPUT,
                                       or to standard output
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


def specs():
    """Every spec of the e2e suite, by file name."""
    return sorted(name for name in os.listdir(os.path.join(ROOT, 'e2e'))
                  if name.endswith('.spec.js'))


def static_members():
    """Everything the static tests run: the app's check, the checkers,
    and each fixture."""
    found = ['check', 'checkers']
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
        runs = [line for line in workflow_file if 'playwright test' in line]
    if not runs:
        found.append('check.yml runs no `playwright test`')
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
    return found


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
