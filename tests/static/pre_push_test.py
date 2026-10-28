#!/usr/bin/env python3
"""Tests of the pre-push hook (quire#973, keyword: pre-push; scripts/pre-push.py).

Each of the four checks has a case that fails when its class occurs, made by injecting
the failure into a copy of the repository's own tree:

 1. a fixture in no group (and one in two, and a group listing a fixture that is gone)
 2. a lock whose sha256 differs from the package repository's at the pin, a version the
    pinned repository does not have, and a clone whose checked-out files are newer than
    the pin (the clone's files are not what is read)
 3. a compiler of another commit, a binary changed after its record, a binary with no record
 4. BATS_PATSOPT_MEM_MB unset or of another value

and the hook itself, run by `git push` from a repository with core.hooksPath .githooks:
the push goes through when all four hold, and each injection refuses it with the check's
name and its fix, leaving the remote without the branch. No bats and no patsopt.

usage: python3 tests/static/pre_push_test.py
"""
import importlib.util
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('pre_push', ROOT / 'scripts' / 'pre-push.py')
pre_push = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pre_push)

PIN = 'a' * 40


def git(*arguments, cwd):
    done = subprocess.run(['git', '-c', 'user.name=t', '-c', 'user.email=t@example.com', *arguments],
                          cwd=cwd, capture_output=True, text=True)
    assert done.returncode == 0, f'git {arguments}: {done.stderr}'
    return done.stdout.strip()


def export_head(directory):
    pre_push_dir = os.getcwd()
    os.chdir(ROOT)
    try:
        pre_push.export_tree('HEAD', directory)
    finally:
        os.chdir(pre_push_dir)
    # the files under test are the working ones, which may not be committed yet
    for name in ('scripts/pre-push.py', '.githooks/pre-push'):
        target = Path(directory) / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, target)


def lock_lines(tree):
    lines = []
    for path in pre_push.lock_paths(str(tree)):
        lines += [line.split() for line in Path(path).read_text().splitlines() if line.strip()]
    return lines


def make_package_repository(directory, lines, digest_of=lambda digest: digest):
    """A package repository with one sidecar for each lock line, one commit; returns the commit."""
    directory.mkdir()
    git('init', '-q', cwd=directory)
    for package, version, digest in lines:
        name = pre_push.sidecar_name(package, version)
        (directory / name).write_text(f'{digest_of(digest)}  {name[:-7]}\n')
    git('add', '.', cwd=directory)
    git('commit', '-q', '-m', 'packages', cwd=directory)
    return git('rev-parse', 'HEAD', cwd=directory)


def make_compiler(directory, commit, content=b'#!/bin/sh\nexit 0\n'):
    directory.mkdir(parents=True, exist_ok=True)
    binary = directory / 'bats'
    binary.write_bytes(content)
    binary.chmod(binary.stat().st_mode | stat.S_IXUSR)
    (directory / 'bats.pin').write_text(f'{commit} {pre_push.sha256_of(str(binary))}\n')
    return directory


class Fixtures(unittest.TestCase):
    def setUp(self):
        self.temp = Path(tempfile.mkdtemp(prefix='pre-push-test-'))
        self.addCleanup(shutil.rmtree, self.temp, ignore_errors=True)
        self.tree = self.temp / 'tree'
        self.tree.mkdir()
        export_head(self.tree)


class GroupsCheck(Fixtures):
    def test_the_repository_passes(self):
        pre_push.check_groups(str(self.tree))

    def test_a_fixture_in_no_group_fails(self):
        (self.tree / 'tests/static/accept/zz-new-fixture').mkdir()
        with self.assertRaises(pre_push.Failure) as failure:
            pre_push.check_groups(str(self.tree))
        self.assertEqual(failure.exception.number, 1)
        self.assertIn('accept/zz-new-fixture is in no group', failure.exception.what)
        self.assertIn('tests/groups.json', failure.exception.fix)

    def test_a_fixture_in_two_groups_fails(self):
        path = self.tree / 'tests/groups.json'
        import json
        groups = json.loads(path.read_text())
        member = groups['static']['rest'][0]
        groups['static']['app'].append(member)
        path.write_text(json.dumps(groups))
        with self.assertRaises(pre_push.Failure) as failure:
            pre_push.check_groups(str(self.tree))
        self.assertIn('is in more than one group', failure.exception.what)

    def test_a_group_naming_a_gone_fixture_fails(self):
        path = self.tree / 'tests/groups.json'
        import json
        groups = json.loads(path.read_text())
        groups['static']['rest'].append('reject/zz-gone')
        path.write_text(json.dumps(groups))
        with self.assertRaises(pre_push.Failure) as failure:
            pre_push.check_groups(str(self.tree))
        self.assertIn('does not exist', failure.exception.what)


class LocksCheck(Fixtures):
    def setUp(self):
        super().setUp()
        self.lines = lock_lines(self.tree)
        self.assertGreater(len(self.lines), 10)
        self.repository = self.temp / 'packages'
        self.pin = make_package_repository(self.repository, self.lines)

    def test_the_repository_locks_resolve_at_the_pin(self):
        pre_push.check_locks(str(self.tree), str(self.repository), self.pin)

    def test_a_lock_of_another_sha256_fails(self):
        lock = self.tree / 'tests/cfi/bats.lock'
        text = lock.read_text()
        first = text.split()[2]
        lock.write_text(text.replace(first, '0' * 64, 1))
        with self.assertRaises(pre_push.Failure) as failure:
            pre_push.check_locks(str(self.tree), str(self.repository), self.pin)
        self.assertEqual(failure.exception.number, 2)
        self.assertIn('tests/cfi/bats.lock:1', failure.exception.what)
        self.assertIn('bats lock --repository', failure.exception.fix)

    def test_a_version_the_pinned_repository_lacks_fails(self):
        lock = self.tree / 'tests/cfi/bats.lock'
        lock.write_text(lock.read_text() + 'array 2099.1.1.1 ' + '1' * 64 + '\n')
        with self.assertRaises(pre_push.Failure) as failure:
            pre_push.check_locks(str(self.tree), str(self.repository), self.pin)
        self.assertIn('array 2099.1.1.1 is not in the package repository', failure.exception.what)

    def test_a_clone_newer_than_the_pin_is_not_what_is_read(self):
        # the machine's clone has moved on: its files hold a package the pin lacks
        newer = ('zip', '2099.1.1.1', '2' * 64)
        name = pre_push.sidecar_name(newer[0], newer[1])
        (self.repository / name).write_text(f'{newer[2]}  x\n')
        git('add', '.', cwd=self.repository)
        git('commit', '-q', '-m', 'newer', cwd=self.repository)
        lock = self.tree / 'bats.lock'
        lock.write_text(lock.read_text() + ' '.join(newer) + '\n')
        with self.assertRaises(pre_push.Failure):
            pre_push.check_locks(str(self.tree), str(self.repository), self.pin)

    def test_a_clone_without_the_pin_fails(self):
        with self.assertRaises(pre_push.Failure) as failure:
            pre_push.check_locks(str(self.tree), str(self.repository), PIN)
        self.assertIn('fetch origin', failure.exception.fix)

    def test_no_repository_fails(self):
        with self.assertRaises(pre_push.Failure) as failure:
            pre_push.check_locks(str(self.tree), None, self.pin)
        self.assertIn('BATS_REPOSITORY', failure.exception.what)


class CompilerCheck(Fixtures):
    def test_the_pinned_compiler_passes(self):
        directory = make_compiler(self.temp / 'bin', PIN)
        pre_push.check_compiler(PIN, str(directory))

    def test_a_compiler_of_another_commit_fails(self):
        directory = make_compiler(self.temp / 'bin', 'b' * 40)
        with self.assertRaises(pre_push.Failure) as failure:
            pre_push.check_compiler(PIN, str(directory))
        self.assertEqual(failure.exception.number, 3)
        self.assertIn('is built from bbbbbbbbbbbb', failure.exception.what)
        self.assertIn('bats.pin', failure.exception.fix)

    def test_a_binary_changed_after_its_record_fails(self):
        directory = make_compiler(self.temp / 'bin', PIN)
        (directory / 'bats').write_bytes(b'#!/bin/sh\nexit 1\n')
        with self.assertRaises(pre_push.Failure) as failure:
            pre_push.check_compiler(PIN, str(directory))
        self.assertIn('another binary', failure.exception.what)

    def test_a_binary_with_no_record_fails(self):
        directory = make_compiler(self.temp / 'bin', PIN)
        (directory / 'bats.pin').unlink()
        with self.assertRaises(pre_push.Failure) as failure:
            pre_push.check_compiler(PIN, str(directory))
        self.assertIn('no bats.pin', failure.exception.what)

    def test_no_compiler_fails(self):
        (self.temp / 'empty').mkdir()
        with self.assertRaises(pre_push.Failure) as failure:
            pre_push.check_compiler(PIN, str(self.temp / 'empty'))
        self.assertIn('no bats on PATH', failure.exception.what)


class MemoryCheck(unittest.TestCase):
    def test_ci_value_passes(self):
        pre_push.check_memory({'BATS_PATSOPT_MEM_MB': pre_push.CI_PATSOPT_MEM_MB})

    def test_unset_fails(self):
        with self.assertRaises(pre_push.Failure) as failure:
            pre_push.check_memory({})
        self.assertEqual(failure.exception.number, 4)
        self.assertIn('unset', failure.exception.what)
        self.assertIn('export BATS_PATSOPT_MEM_MB=', failure.exception.fix)

    def test_another_value_fails(self):
        with self.assertRaises(pre_push.Failure):
            pre_push.check_memory({'BATS_PATSOPT_MEM_MB': '8192'})

    def test_the_constant_is_what_ci_runs(self):
        # CI takes the setup action's default: no workflow of quire gives another value
        for workflow in (ROOT / '.github' / 'workflows').glob('*.yml'):
            self.assertNotIn('patsopt-mem-mb', workflow.read_text(), workflow.name)


class Hook(Fixtures):
    """`git push` from a repository whose core.hooksPath is .githooks."""

    def setUp(self):
        super().setUp()
        lines = lock_lines(self.tree)
        self.packages = self.temp / 'packages'
        pin = make_package_repository(self.packages, lines)
        self.compiler_commit = 'c' * 40
        (self.tree / '.github/repository-version').write_text(pin + '\n')
        (self.tree / '.github/bats-version').write_text(self.compiler_commit + '\n')
        self.bin = make_compiler(self.temp / 'bin', self.compiler_commit)
        self.remote = self.temp / 'remote.git'
        git('init', '-q', '--bare', str(self.remote), cwd=self.temp)
        git('init', '-q', '-b', 'work', cwd=self.tree)
        git('config', 'core.hooksPath', '.githooks', cwd=self.tree)
        git('add', '-A', '-f', '.', cwd=self.tree)
        git('commit', '-q', '-m', 'base', '--no-verify', cwd=self.tree)
        self.environment = {**os.environ, 'PATH': f'{self.bin}:{os.environ["PATH"]}',
                            'BATS_REPOSITORY': str(self.packages), 'BATS_PATSOPT_MEM_MB': '4096'}

    def push(self, **changes):
        environment = {**self.environment, **changes}
        environment = {key: value for key, value in environment.items() if value is not None}
        return subprocess.run(['git', 'push', str(self.remote), 'work'], cwd=self.tree, env=environment,
                              capture_output=True, text=True)

    def remote_has_branch(self):
        return subprocess.run(['git', 'rev-parse', '--verify', '-q', 'work'], cwd=self.remote, capture_output=True).returncode == 0

    def refused(self, done, check):
        self.assertNotEqual(done.returncode, 0, done.stderr)
        self.assertIn(f'pre-push: check {check}', done.stderr)
        self.assertIn('fix:', done.stderr)
        self.assertFalse(self.remote_has_branch())

    def test_all_four_hold_and_the_push_goes_through(self):
        done = self.push()
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertTrue(self.remote_has_branch())

    def test_a_fixture_in_no_group_refuses_the_push(self):
        (self.tree / 'tests/static/reject/zz-new').mkdir()
        (self.tree / 'tests/static/reject/zz-new/src.bats').write_text('x\n')
        git('add', '-A', '-f', '.', cwd=self.tree)
        git('commit', '-q', '-m', 'fixture', '--no-verify', cwd=self.tree)
        self.refused(self.push(), '1 (groups)')

    def test_a_lock_that_mismatches_the_pinned_repository_refuses_the_push(self):
        lock = self.tree / 'bats.lock'
        lock.write_text(lock.read_text().replace(lock.read_text().split()[2], '0' * 64, 1))
        git('commit', '-q', '-a', '-m', 'lock', '--no-verify', cwd=self.tree)
        self.refused(self.push(), '2 (locks)')

    def test_a_compiler_of_another_commit_refuses_the_push(self):
        make_compiler(self.bin, 'd' * 40)
        self.refused(self.push(), '3 (compiler)')

    def test_the_memory_variable_unset_refuses_the_push(self):
        self.refused(self.push(BATS_PATSOPT_MEM_MB=None), '4 (memory)')

    def test_checks_run_in_order_and_stop_at_the_first(self):
        make_compiler(self.bin, 'd' * 40)
        done = self.push(BATS_PATSOPT_MEM_MB=None)
        self.refused(done, '3 (compiler)')
        self.assertNotIn('check 4', done.stderr)

    def test_a_deletion_runs_no_check(self):
        # a branch deleted from the remote has no commit to check
        subprocess.run(['git', 'push', '--no-verify', str(self.remote), 'work'], cwd=self.tree, capture_output=True)
        deleted = subprocess.run(['git', 'push', str(self.remote), ':work'], cwd=self.tree,
                                 env={k: v for k, v in self.environment.items() if k != 'BATS_PATSOPT_MEM_MB'},
                                 capture_output=True, text=True)
        self.assertEqual(deleted.returncode, 0, deleted.stderr)


if __name__ == '__main__':
    unittest.main()
