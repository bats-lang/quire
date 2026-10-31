// A real process in state D for as long as the test wants (keyword: blocked watchdog, quire#972), with no C and no root.
//
// A parent inside vfork waits for its child to exec or exit, and that wait is a killable one, so /proc/<pid>/stat shows D (wchan kernel_clone). glibc's
// posix_spawn is a vfork; the child here opens a FIFO nobody writes, so it sits in open(2) before the exec, and the parent stays in D until the test opens the
// FIFO. Avenue exhausted for a JS-only form: node's libuv spawns with fork and a pipe (the parent waits in S), and has no vfork; python3's os.posix_spawn is the
// one call that makes it, and python3 is on the runner (the static tests need it). Needs no sudo: tried and ruled out, a throttled loop device and FUSE (root and
// /dev/fuse), tracefs trace_pipe (S), ptrace stops (t).
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, openSync, closeSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { processState } from './preflight.js';

const PARENT = `
import os, sys
os.posix_spawn('/bin/true', ['true'], {}, file_actions=[(os.POSIX_SPAWN_OPEN, 0, sys.argv[1], os.O_RDONLY, 0)])
`;

/**
 * Starts the process and resolves once its state is D, or rejects after waitMs. Returns { pid, release }: release() lets it go (opens the FIFO) and removes
 * the directory; call it in a finally, it is safe to call twice.
 */
export async function startBlockedProcess({ waitMs = 10000 } = {}) {
  const directory = mkdtempSync(join(tmpdir(), 'blocked-'));
  const fifo = join(directory, 'gate');
  const made = spawnSync('mkfifo', [fifo]);
  if (made.status !== 0) { rmSync(directory, { recursive: true, force: true }); throw new Error(`mkfifo failed: ${made.stderr}`); }
  const child = spawn('python3', ['-I', '-c', PARENT, fifo], { stdio: 'ignore' });
  let released = false;
  const release = () => {
    if (released) return;
    released = true;
    try { closeSync(openSync(fifo, 'r+')); } catch (error) { /* the process is gone already */ }
    child.kill('SIGKILL'); // the child of the vfork is released by the open above; this ends the parent if it never got that far
    rmSync(directory, { recursive: true, force: true });
  };
  const deadline = Date.now() + waitMs;
  while (Date.now() < deadline) {
    if (processState(child.pid) === 'D') return { pid: child.pid, release };
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  const last = processState(child.pid);
  release();
  throw new Error(`the process did not reach state D in ${waitMs} ms (last state: ${last})`);
}
