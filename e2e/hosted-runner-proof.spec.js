/**
 * TEMPORARY, a deliberate diagnostic (quire#575, #591, PR #662): a real
 * renderer is hung the way the real freeze is (idle CPU, no answer, in an
 * untimed wait), with no SIGSTOP, so the whole native capture runs as it
 * would on a freeze, on a hosted runner as the non-root user: gdb through
 * `sudo -n`, the backtraces, the madvise-trimmed core, gzip, the artifact, and
 * the teardown. It prints what it found (sudo's rules, ptrace_scope, gdb, the
 * core's size, how long the renderer stood still) so a failure can be read
 * from the log. It is removed once it has been seen to pass there.
 *
 * The hang: a synchronous XHR on the page's main thread to a local server that
 * never answers (Chromium allows it on the main thread), so the main thread is
 * blocked and idle until the server lets go.
 */

import { createServer } from 'node:http';
import { existsSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { test, expect } from './fixtures.js';
import { CORE_GZ_MAX_BYTES, CORE_MAX_BYTES, FROZEN_CPU_SECONDS, NATIVE_MOST_MS } from './stall-capture.js';

const say = (key, value) => console.error(`[hosted-proof] ${key}: ${typeof value === 'string' ? value : JSON.stringify(value)}`);
const sh = (command, args) => {
  const out = spawnSync(command, args, { encoding: 'utf8', timeout: 15000 });
  return `${out.stdout || ''}${out.stderr || ''}`.trim().slice(0, 4000) || `(exit ${out.status}, no output)`;
};

/** What of gdb, sudo, timeout, prlimit and pkill runs now (their command lines hold gdb's flags or the watch's token). */
const leftBehind = () => spawnSync('ps', ['-eo', 'pid,stat,args'], { encoding: 'utf8' }).stdout.split('\n')
  .filter((line) => /(gdb|prlimit) .*-batch|QUIRE_STALL_|\bpkill\b/.test(line) && !/ps -eo/.test(line)).join('\n');

test('hosted-runner proof: a deliberately hung page', async ({ page, stallWatch }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'one project is enough to see the runner');
  test.setTimeout(testInfo.timeout + NATIVE_MOST_MS);
  const facts = {
    who: sh('id', []),
    uname: sh('uname', ['-a']),
    cpus: sh('nproc', []),
    sudo: sh('sudo', ['-n', '-l']),
    ptraceScope: sh('cat', ['/proc/sys/kernel/yama/ptrace_scope']),
    gdb: sh('gdb', ['--version']).split('\n')[0],
    libc6dbg: sh('dpkg-query', ['-W', 'libc6-dbg']),
    disk: sh('df', ['-h', '.', '/tmp']),
    memory: sh('free', ['-m']),
  };
  for (const [key, value] of Object.entries(facts)) say(key, value);

  const held = new Set();
  const server = createServer(() => { /* never answers */ });
  server.on('connection', (socket) => held.add(socket));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  try {
    await page.setContent('<!doctype html><title>Hung</title><p>Hung</p>');
    const session = await stallWatch.session(page);
    const began = Date.now();
    await session.send('Runtime.evaluate', { expression: `setTimeout(() => { const request = new XMLHttpRequest(); request.open('GET', 'http://127.0.0.1:${port}/never', false); request.send(); }, 0)` });
    const capture = await stallWatch.next(page, 30000 + NATIVE_MOST_MS);
    const took = Date.now() - began;
    say('capture reason', capture.reason);
    say('capture verdict', capture.verdict);
    say('capture answers', capture.answers);
    say('capture renderer cpu', capture.rendererCpu.map((renderer) => `${renderer.pid}: ${renderer.cpuSeconds} s`));
    say('capture presumedBusy', capture.presumedBusy || 'no');
    say('capture native unavailable', capture.native && capture.native.unavailable || 'no');
    const renderer = capture.native && capture.native.renderers && capture.native.renderers.find((each) => each.gdbStacks);
    if (renderer) {
      say('main thread syscall', renderer.kernel.tasks.find((task) => task.tid === renderer.pid));
      say('gdb', { ok: renderer.gdbStacks.ok, exit: renderer.gdbStacks.exitCode, ms: renderer.gdbStacks.ms, error: renderer.gdbStacks.error, stderr: renderer.gdbStacks.stderr.slice(0, 1500) });
      say('main thread frames', renderer.gdbStacks.mainThread && renderer.gdbStacks.mainThread.frames.map((frame) => frame.text.slice(0, 140)));
      say('core', renderer.core);
      say('binary', renderer.binary);
    }
    // everything found, as an attachment the artifact keeps (stall-capture-*.json)
    const path = testInfo.outputPath('stall-capture-proof-diagnostics.json');
    writeFileSync(path, JSON.stringify({ facts, took, capture }, null, 2));
    await testInfo.attach('hosted-proof', { path, contentType: 'application/json' });
    say('capture took (ms, from the hang to the capture)', took);
    say('left behind after the capture', leftBehind() || 'nothing');

    // the proof's assertions
    expect(capture.answers.task.answered, 'the main thread answers no task').toBe(false);
    expect(Math.max(...capture.rendererCpu.map((each) => each.cpuSeconds)), 'it is idle, not busy').toBeLessThan(FROZEN_CPU_SECONDS);
    expect(capture.presumedBusy).toBeUndefined();
    expect(capture.native, 'a native capture was taken').toBeTruthy();
    expect(capture.native.unavailable, 'gdb works on this runner').toBeUndefined();
    expect(renderer, 'a renderer has native stacks').toBeTruthy();
    expect(renderer.gdbStacks.ok, `${renderer.gdbStacks.error} ${renderer.gdbStacks.stderr}`).toBe(true);
    const frames = renderer.gdbStacks.threads.flatMap((thread) => thread.frames);
    const library = frames.filter((frame) => frame.module && /(libc|ld-linux[^/]*)\.so/.test(frame.module));
    expect(library.some((frame) => /^#\d+\s+0x[0-9a-f]+ in (?!\?)\S+/.test(frame.text) || /^#\d+\s+(?!0x)\S+ \(/.test(frame.text)), 'libc frames are named').toBe(true);
    expect(renderer.core.kept, JSON.stringify(renderer.core)).toBe(true);
    expect(renderer.core.bytes).toBeLessThanOrEqual(CORE_MAX_BYTES);
    expect(renderer.core.gzBytes).toBeLessThanOrEqual(CORE_GZ_MAX_BYTES);
    expect(existsSync(renderer.core.file)).toBe(true);
    // the core opens in gdb with the binary it names
    const raw = testInfo.outputPath('proof-opened.core');
    expect(spawnSync('sh', ['-c', 'gzip -dc "$1" > "$2"', 'sh', renderer.core.file, raw], { timeout: 120000 }).status).toBe(0);
    const opened = spawnSync('gdb', ['-batch', '-nx', '-q', '-iex', 'set debuginfod enabled off', '-ex', 'thread 1', '-ex', 'bt 3', renderer.exe, raw], { encoding: 'utf8', timeout: 180000 });
    say('core opened in gdb', `${opened.stdout}${opened.stderr}`.trim().split('\n').slice(-6));
    unlinkSync(raw);
    expect(opened.stdout).toContain(renderer.gdbStacks.mainThread.frames[0].pc.replace(/^0x0*/, ''));
    expect(leftBehind(), 'nothing of gdb, prlimit, timeout, sudo or pkill is left').toBe('');
    say('core file', { bytes: statSync(renderer.core.file).size });
  } finally {
    // let the page go: the sync request fails, the main thread runs again, and the renderer is not broken
    for (const socket of held) socket.destroy();
    server.close();
  }
  await expect.poll(() => page.evaluate(() => 1 + 1), { timeout: 30000 }).toBe(2);
  // and the watch's teardown (stop, which ends what still runs) is the fixture's own, after this
  say('the page answers again', true);
});
