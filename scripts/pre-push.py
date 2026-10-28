#!/usr/bin/env python3
"""The pre-push hook's checks (quire#973, keyword: pre-push): what CI rejects in its
first minutes, and needs no judgment, run before the commits leave the machine.

Git runs .githooks/pre-push with the remote's name and URL and, on standard input, a
line `<local ref> <local sha> <remote ref> <remote sha>` for each ref being pushed. For
each ref that is not a deletion, in this order, and stopping at the first failure:

 1. groups    every spec and every static fixture of the pushed commit is in exactly one
              group of tests/groups.json (`scripts/ci-groups.py matrix`, CI's `plan` job)
 2. locks     every bats.lock of the pushed commit names only (package, version, sha256)
              the package repository holds at the commit of .github/repository-version
              (the clone at $BATS_REPOSITORY is read at that commit, whatever it has checked out)
 3. compiler  the `bats` on PATH is the one built from the commit of .github/bats-version:
              its sha256 is the one recorded beside it in `bats.pin` (`<commit> <sha256>`)
 4. memory    BATS_PATSOPT_MEM_MB is CI's value, in this shell

A failure prints `pre-push: check <n> (<name>) failed: <what>` and `fix: <the fix>`, and
exits 1. `git push --no-verify` skips the hook; the sweep reports a transcript that has it.

Why not bats: this runs before a compiler is known to be right (check 3 is that), and the
checks read git objects of two repositories and a clone of the package repository at a
commit, which no bats program does today; check 1 is the python CI itself runs.
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

ZERO = '0' * 40
# CI's value: the default of `patsopt-mem-mb` in bats's setup action, which quire's
# workflows do not override (pre_push_test.py checks that none does)
CI_PATSOPT_MEM_MB = '4096'


class Failure(Exception):
    def __init__(self, number, name, what, fix):
        super().__init__(what)
        self.number, self.name, self.what, self.fix = number, name, what, fix


def git(*arguments, cwd=None, binary=False):
    done = subprocess.run(['git', *arguments], cwd=cwd, capture_output=True)
    if done.returncode != 0:
        raise RuntimeError(f'git {" ".join(arguments)}: {done.stderr.decode(errors="replace").strip()}')
    return done.stdout if binary else done.stdout.decode()


def export_tree(commit, directory):
    """The tree of `commit` (a repository's own, the current directory's) in `directory`."""
    archive = subprocess.run(['git', 'archive', '--format=tar', commit], capture_output=True)
    if archive.returncode != 0:
        raise RuntimeError(f'git archive {commit}: {archive.stderr.decode(errors="replace").strip()}')
    unpacked = subprocess.run(['tar', '-x', '-C', directory], input=archive.stdout, capture_output=True)
    if unpacked.returncode != 0:
        raise RuntimeError(f'tar: {unpacked.stderr.decode(errors="replace").strip()}')


def read_pin(tree, name):
    with open(os.path.join(tree, '.github', name)) as pin_file:
        pin = pin_file.read().strip()
    if not re.fullmatch(r'[0-9a-f]{40}', pin):
        raise RuntimeError(f'.github/{name} is not a full lowercase commit: {pin!r}')
    return pin


def check_groups(tree):
    """Check 1: `scripts/ci-groups.py matrix` of the pushed tree, as CI's plan job runs it."""
    done = subprocess.run([sys.executable, '-I', os.path.join(tree, 'scripts', 'ci-groups.py'), 'matrix'],
                          cwd=tree, capture_output=True, text=True, env={**os.environ, 'GITHUB_OUTPUT': ''})
    if done.returncode != 0:
        raise Failure(1, 'groups', (done.stderr + done.stdout).strip(),
                      'put the fixture or spec in one group of tests/groups.json (or remove the name of one that is gone)')


def lock_paths(tree):
    found = []
    for directory, names, files in os.walk(tree):
        names[:] = [name for name in names if name not in ('.git', 'node_modules', 'bats_modules', 'build')]
        if 'bats.lock' in files:
            found.append(os.path.join(directory, 'bats.lock'))
    return sorted(found)


def sidecar_name(package, version):
    return f'{package.replace("/", "_")}_{version}.bats.sha256'


def check_locks(tree, repository, pin):
    """Check 2: each line `<package> <version> <sha256>` of each bats.lock is a sidecar of the
    package repository at `pin`, read from the commit and not from the clone's files."""
    if not repository:
        raise Failure(2, 'locks', 'BATS_REPOSITORY is not set, so the package repository at the pin cannot be read',
                      f'clone bats-lang/repository-prototype and set BATS_REPOSITORY to it (CI is at {pin})')
    have = subprocess.run(['git', '-C', repository, 'cat-file', '-e', f'{pin}^{{commit}}'], capture_output=True)
    if have.returncode != 0:
        raise Failure(2, 'locks', f'{repository} does not have the commit {pin} of .github/repository-version',
                      f'git -C {repository} fetch origin {pin}')
    wrong = []
    for path in lock_paths(tree):
        shown = os.path.relpath(path, tree)
        with open(path) as lock_file:
            for number, line in enumerate(lock_file, 1):
                fields = line.split()
                if not fields or fields[0].startswith('#'):
                    continue
                if len(fields) != 3:
                    wrong.append(f'{shown}:{number}: not "<package> <version> <sha256>": {line.strip()}')
                    continue
                package, version, digest = fields
                sidecar = subprocess.run(['git', '-C', repository, 'show', f'{pin}:{sidecar_name(package, version)}'],
                                         capture_output=True, text=True)
                if sidecar.returncode != 0:
                    wrong.append(f'{shown}:{number}: {package} {version} is not in the package repository at {pin[:12]}')
                elif sidecar.stdout.split()[:1] != [digest]:
                    wrong.append(f'{shown}:{number}: {package} {version} has sha256 {digest[:16]}.., '
                                 f'the repository at {pin[:12]} has {sidecar.stdout.split()[:1]}')
    if wrong:
        raise Failure(2, 'locks', '\n'.join(wrong),
                      f'relock against the pin: bats lock --repository <clone at {pin}> in the directory of each lock named above')


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as binary:
        for block in iter(lambda: binary.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def check_compiler(pin, path_value):
    """Check 3: the `bats` on PATH has the sha256 recorded in the `bats.pin` beside it, and the
    commit recorded there is the pin of .github/bats-version."""
    found = shutil.which('bats', path=path_value)
    recipe = ('in a checkout of bats at the pin: make -C bootstrap/c release/bats, then write '
              '`printf "%s %s\\n" "$(git rev-parse HEAD)" "$(sha256sum release/bats | cut -d" " -f1)" > release/bats.pin` '
              'beside the binary, and put that directory first on PATH')
    if not found:
        raise Failure(3, 'compiler', 'there is no bats on PATH', recipe)
    found = os.path.realpath(found)
    record = os.path.join(os.path.dirname(found), 'bats.pin')
    if not os.path.isfile(record):
        raise Failure(3, 'compiler', f'{found} has no bats.pin beside it, so its commit is unknown', recipe)
    with open(record) as record_file:
        fields = record_file.read().split()
    if len(fields) != 2:
        raise Failure(3, 'compiler', f'{record} is not "<commit> <sha256>"', recipe)
    commit, recorded = fields
    actual = sha256_of(found)
    if actual != recorded:
        raise Failure(3, 'compiler', f'{found} has sha256 {actual[:16]}.., {record} records {recorded[:16]}..: another binary', recipe)
    if commit != pin:
        raise Failure(3, 'compiler', f'{found} is built from {commit[:12]}, .github/bats-version is {pin[:12]}', recipe)


def check_memory(environment):
    """Check 4: BATS_PATSOPT_MEM_MB is CI's, as the setup action sets it."""
    value = environment.get('BATS_PATSOPT_MEM_MB')
    if value != CI_PATSOPT_MEM_MB:
        shown = 'unset' if value is None else repr(value)
        raise Failure(4, 'memory', f'BATS_PATSOPT_MEM_MB is {shown}, CI runs with {CI_PATSOPT_MEM_MB}',
                      f'export BATS_PATSOPT_MEM_MB={CI_PATSOPT_MEM_MB} in the shell that pushes (a patsopt that needs more fails there, as in CI)')


def run(commits, environment, path_value):
    """The four checks, in order, for each pushed commit; the first failure raises."""
    for commit in commits:
        with tempfile.TemporaryDirectory(prefix='pre-push-') as tree:
            export_tree(commit, tree)
            check_groups(tree)
            check_locks(tree, environment.get('BATS_REPOSITORY'), read_pin(tree, 'repository-version'))
            check_compiler(read_pin(tree, 'bats-version'), path_value)
            check_memory(environment)


def main(arguments):
    commits = []
    for line in sys.stdin:
        fields = line.split()
        if len(fields) == 4 and fields[1] != ZERO and fields[1] not in commits:
            commits.append(fields[1])
    try:
        run(commits, os.environ, os.environ.get('PATH', ''))
    except Failure as failure:
        print(f'pre-push: check {failure.number} ({failure.name}) failed:\n{failure.what}\nfix: {failure.fix}', file=sys.stderr)
        return 1
    except RuntimeError as error:
        print(f'pre-push: the checks could not run: {error}', file=sys.stderr)
        return 1
    if commits:
        print(f'pre-push: groups, locks, compiler and memory ok for {len(commits)} commit(s)')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
