/**
 * The stall watch itself (e2e/stall-capture.js, #244): a page that runs
 * an endless loop on purpose, in script and in wasm, is captured by the
 * watch on its own, and the capture names the loop's function. The page
 * is a test page of its own (setContent), not the app.
 *
 * The same capture holds the native stacks (#575, #591) of a renderer that is
 * frozen, no CPU and no answer: gdb's backtrace of every thread, the kernel's
 * stack, wait channel and system call of every thread, and what resolves their
 * raw addresses offline. A renderer that is only busy (a loop, a heavy layout)
 * is never attached to: gdb stops the process. Frozen is made by SIGSTOP of the
 * renderer, armed or not. Where gdb, sudo or ptrace is not there a test says so
 * and skips, on CI too: nothing about gdb turns a run red (a stall-capture
 * failure with gdb present and allowed still fails this spec's group).
 */

import { createServer } from 'node:http';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
import { once } from 'node:events';
import { tmpdir } from 'node:os';
import { delimiter, join } from 'node:path';
import { test, expect } from './fixtures.js';
import { attempted, attemptsOf, metricsBetween, noted } from './attempt-log.js';
import { SAMPLE_EVERY_MS, runnerLoad, sampleRunner } from './runner-load.js';
import { keepHistory } from './page-history.js';
import { gunzipSync } from 'node:zlib';
import { keepBrowserTrace, keepKernel, ringSeen, serialRun, startBrowserTrace, startKernel, stopKernel, wanted } from './flight-recorder.js';
import { arm, capture, lasting, cgroupEvidence, summary, CANNOT_ATTACH, CAPTURE_MOST_MS, CORE_GZ_MAX_BYTES, CORE_MAX_BYTES, FROZEN_CPU_SECONDS, KERNEL_LOG_LINES, kernelLog, nativeScope, nativeStacks, NATIVE_MOST_MS, READ_MOST, TEARDOWN_MOST_MS, whichExecutable } from './stall-capture.js';

/** Resolves when the child has been started (its program is running). */
const started = (child) => once(child, 'spawn');

/** A wasm module whose one export, `spin`, is a function named spinInWasm that loops forever. */
const SPIN_MODULE = (() => {
  const name = [...'spinInWasm'].map((character) => character.charCodeAt(0));
  const nameSubsection = [0x01, 1 + 1 + 1 + name.length, 0x01, 0x00, name.length, ...name];
  const nameSection = [0x04, ...[...'name'].map((character) => character.charCodeAt(0)), ...nameSubsection];
  const body = [0x00, 0x03, 0x40, 0x0c, 0x00, 0x0b, 0x0b]; // no locals; loop: br 0; end; end
  return [
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
    0x01, 0x04, 0x01, 0x60, 0x00, 0x00,                         // type: () -> ()
    0x03, 0x02, 0x01, 0x00,                                     // one function of that type
    0x07, 0x08, 0x01, 0x04, 0x73, 0x70, 0x69, 0x6e, 0x00, 0x00, // export "spin"
    0x0a, body.length + 2, 0x01, body.length, ...body,          // its code
    0x00, nameSection.length, ...nameSection,                   // its name
  ];
})();

const LOOPS = `<!doctype html><title>Endless loops</title><script>
function spinForever() { let turns = 0; for (;;) { turns += 1; } }
function spinForeverAnnounced() { console.log('spinning'); spinForever(); }
function enterWasm(bytes) {
  const instance = new WebAssembly.Instance(new WebAssembly.Module(new Uint8Array(bytes)));
  instance.exports.spin();
}
</script>`;

/**
 * Starts an endless loop on the page, through the watch's session: a
 * Playwright action would wait for its trace snapshot after it, which a
 * page that loops never answers.
 */
async function startLoop(page, stallWatch, expression) {
  await page.setContent(LOOPS);
  const session = await stallWatch.session(page);
  await session.send('Runtime.evaluate', { expression });
}

/** startLoop, resolved when the page is in the loop: it says so (a console message reaches this process while the page loops). */
async function startLoopHeard(page, stallWatch) {
  await page.setContent(LOOPS);
  const heard = page.waitForEvent('console', (message) => message.text() === 'spinning');
  const session = await stallWatch.session(page);
  await session.send('Runtime.evaluate', { expression: 'setTimeout(spinForeverAnnounced, 0)' });
  await heard;
}

/**
 * Ends the page's endless loop, so the page answers again and closes as
 * usual: through the watch's session, since a session made now could not
 * attach to the page while it loops.
 */
async function endLoop(page, stallWatch) {
  const session = await stallWatch.session(page);
  // the terminate command interrupts running script, so it is answered
  await session.send('Runtime.terminateExecution');
  await expect.poll(() => page.evaluate(() => 1)).toBe(1);
}

/**
 * A machine that cannot take the native stacks (gdb missing, ptrace or sudo
 * refused): the capture says `native capture unavailable` and carries on, and
 * the test skips with that reason, on CI too: a missing gdb must never turn a
 * run red (the first CI run shows whether the runner takes the stacks).
 */
function unavailable(reason) {
  test.skip(true, reason);
}

/**
 * The long tests (a 12 s busy page, a frozen renderer, a teardown) look at the renderer
 * and the machine, which no project changes, and cost 2 to 3 minutes: they run in desktop
 * only, and skip, saying why, in the others.
 */
function desktopOnly(testInfo) {
  test.skip(testInfo.project.name !== 'desktop', 'the renderer and the machine do not depend on the project: once, in desktop, is enough');
}

/** Every renderer process of the browser: the pids. */
async function rendererPids(browser) {
  const session = await browser.newBrowserCDPSession();
  try {
    const { processInfo } = await session.send('SystemInfo.getProcessInfo');
    return processInfo.filter((process) => process.type === 'renderer').map((process) => process.id);
  } finally {
    await session.detach();
  }
}

/**
 * Freezes these renderers (SIGSTOP: no CPU, no answer to anything, as #575's and
 * #591's), runs `during`, and always lets them go again (SIGCONT).
 */
async function frozen(pids, during) {
  for (const pid of pids) process.kill(pid, 'SIGSTOP');
  try {
    return await during();
  } finally {
    for (const pid of pids) { try { process.kill(pid, 'SIGCONT'); } catch (gone) { /* it ended */ } }
  }
}

/** What a capture of a busy page holds: gdb was never attached to a renderer that used CPU. */
function expectBusyNotFrozen(capture) {
  expect(capture.native, 'a busy renderer is not attached to').toBeUndefined();
  const busiest = Math.max(...capture.rendererCpu.map((process) => process.cpuSeconds));
  expect(busiest, 'the renderer used at least the CPU that separates busy from frozen').toBeGreaterThanOrEqual(FROZEN_CPU_SECONDS);
}

/**
 * What a capture of a frozen renderer holds of its native side (#575, #591):
 * skips where gdb or ptrace is not there, otherwise asserts everything.
 */
function expectNativeStacks(capture, pids) {
  expect(capture.native.error).toBeUndefined();
  if (capture.native.unavailable) unavailable(capture.native.unavailable);
  const renderer = capture.native.renderers.find((each) => pids.includes(each.pid));
  expect(renderer, 'the frozen renderer has native stacks').toBeTruthy();
  const stacks = renderer.gdbStacks;
  if (!stacks.ok && CANNOT_ATTACH.test(`${stacks.stderr}\n${stacks.text}\n${stacks.error}`)) {
    unavailable(`gdb cannot attach on this machine (ptrace_scope ${capture.native.ptraceScope}, root ${capture.native.root}): ${stacks.stderr}`);
  }
  // what resolves addresses offline: the binary, its build id, where it is loaded
  expect(renderer.exe).toMatch(/headless_shell|chrome/);
  expect(renderer.buildId).toMatch(/^[0-9a-f]{16,}$/);
  expect(renderer.exeBase).toMatch(/^[0-9a-f]+$/);
  expect(renderer.exeMaps.length).toBeGreaterThan(0);
  expect(renderer.modules.some((module) => module.path === renderer.exe && module.base === renderer.exeBase)).toBe(true);
  expect(renderer.anonymousCode.length, 'JIT code lives in executable memory with no file').toBeGreaterThan(0);
  // the kernel's view of every thread, the main thread (tid = pid) among them
  expect(renderer.kernel.tasks.length).toBeGreaterThan(2);
  // the new fields (#575): where the user-space stacks came from, ptrace's setting, the other browser processes
  expect(renderer.userSpaceStacks).toBe('gdb');
  expect(renderer.fallbackStacks, 'the fallback tools are asked only when gdb gave none').toBeUndefined();
  expect(typeof capture.native.ptraceScope).toBe('string');
  expect(typeof capture.native.root).toBe('boolean');
  expect(renderer.exe).toBeTruthy();
  expect(capture.native.browserProcesses.length, 'the browser process is noted').toBeGreaterThan(0);
  for (const other of capture.native.browserProcesses) expect(other.kernel.tasks.length, `${other.type} ${other.pid} has threads`).toBeGreaterThan(0);
  expect(capture.native.browserProcesses.some((other) => other.type === 'browser')).toBe(true);
  const main = renderer.kernel.tasks.find((task) => task.tid === renderer.pid);
  expect(main, 'the main thread is a task').toBeTruthy();
  expect(main.state).toMatch(/^[RSDtT]$/);
  for (const task of renderer.kernel.tasks) expect(task.syscall, `the syscall of ${task.comm}`).not.toBe('');
  // gdb's backtrace of every thread
  expect(stacks.ok, `${stacks.error} ${stacks.stderr}`).toBe(true);
  expect(stacks.threadCount).toBe(renderer.kernel.tasks.length);
  expect(stacks.threads.length, 'the thread list of a hung page is not empty').toBeGreaterThan(0);
  expect(stacks.mainThread, 'gdb listed the main thread (LWP = pid)').toBeTruthy();
  const frames = stacks.mainThread.frames;
  expect(frames.length).toBeGreaterThan(0);
  // every frame's address is in a mapping, and the stack reaches the binary at an offset that resolves offline
  expect(frames[0].module).toBeTruthy();
  expect(frames.some((frame) => frame.module === renderer.exe && /^0x[0-9a-f]+$/.test(frame.offset))).toBe(true);
  // symbols (B): the system library's frames are named (exported functions by the dynamic symbols
  // alone; libc6-dbg, installed by the job where it can be, names the internal ones too); the
  // browser's are named when it is not stripped, and else an offset from its recorded load address
  // (any thread's: the main thread of a renderer stopped at a random moment may be in Blink's code)
  expectLibraryFramesNamed(stacks.threads.flatMap((thread) => thread.frames));
  expect(renderer.binary.version).toMatch(/\d+\.\d+/);
  expect(typeof renderer.binary.hasSymtab).toBe('boolean');
  const inBinary = frames.filter((frame) => frame.module === renderer.exe);
  if (renderer.binary.hasSymtab) expect(inBinary.some((frame) => namedFrame(frame.text))).toBe(true);
  else for (const frame of inBinary) expect(frame.offset).toMatch(/^0x[0-9a-f]+$/);
  expect(renderer.libraries.some((library) => /libc\.so/.test(library.path) && /^[0-9a-f]{16,}$/.test(library.buildId))).toBe(true);
}

/** A frame of gdb's text that has a function's name (and not ?? or ???). */
function namedFrame(text) {
  return /^#\d+\s+0x[0-9a-f]+ in (?!\?)\S+/.test(text) || /^#\d+\s+(?!0x)\S+ \(/.test(text);
}

/** At least one frame in the C library or the loader is named: what symbols the machine has. */
function expectLibraryFramesNamed(frames) {
  const library = frames.filter((frame) => frame.module && /(libc|ld-linux[^/]*|libpthread)\.so/.test(frame.module));
  expect(library.length, 'the stack runs through the C library').toBeGreaterThan(0);
  expect(library.some((frame) => namedFrame(frame.text)), `a named frame among ${library.map((frame) => frame.text.slice(0, 60)).join(' | ')}`).toBe(true);
}

test('a page in an endless script loop is captured in that loop, and gdb is not attached to it', async ({ page, stallWatch }) => {
  await startLoop(page, stallWatch, 'setTimeout(spinForever, 0)');
  const capture = await stallWatch.next(page, 20000);
  expect(capture.reason).toContain('did not answer');
  expect(capture.answers.interrupt.answered).toBe(true);
  expect(capture.answers.task.answered).toBe(false);
  expect(capture.paused.frames[0].functionName).toBe('spinForever');
  expect(capture.verdict).toContain('spinForever');
  await endLoop(page, stallWatch);
  // a loop is busy, not frozen: it spends a second of CPU a second
  expectBusyNotFrozen(capture);
});

test('a page in an endless wasm loop is captured in that loop, and gdb is not attached to it', async ({ page, stallWatch }) => {
  await startLoop(page, stallWatch, `setTimeout(() => enterWasm(${JSON.stringify(SPIN_MODULE)}), 0)`);
  const capture = await stallWatch.next(page, 20000);
  const [inWasm, caller] = capture.paused.frames;
  expect(inWasm.functionName).toContain('spinInWasm');
  expect(inWasm.url).toMatch(/^wasm:\/\//);
  expect(caller.functionName).toBe('enterWasm');
  await endLoop(page, stallWatch);
  expectBusyNotFrozen(capture);
});

test('a page\'s recent console messages, errors and requests are in its capture, with the requests in flight (#575)', async ({ page, stallWatch }) => {
  await page.route('**/history-never-answered', () => {});
  await page.route('**/history-refused', (route) => route.abort('failed'));
  await page.setContent('<!doctype html><title>History</title><p>History</p>');
  // the page's error and its unanswered request reach this process as events: they are in the history when both have been heard
  const heard = Promise.all([page.waitForEvent('pageerror'), page.waitForEvent('request', (request) => /\/history-never-answered$/.test(request.url()))]);
  await page.evaluate(async () => {
    console.warn('history-marker');
    setTimeout(() => { throw new Error('history-error'); }, 0);
    await fetch('http://history.test/history-refused').catch(() => {});
    fetch('http://history.test/history-never-answered').catch(() => {});
  });
  await heard;
  await startLoop(page, stallWatch, 'setTimeout(spinForever, 0)');
  const capture = await stallWatch.next(page, 20000);
  await endLoop(page, stallWatch);
  const history = capture.history;
  expect(history.console.some((each) => each.type === 'warning' && each.text === 'history-marker')).toBe(true);
  expect(history.pageerror.some((each) => each.message === 'history-error')).toBe(true);
  expect(history.requestfailed.some((each) => /\/history-refused$/.test(each.url) && /ERR_FAILED/.test(each.failure))).toBe(true);
  const flying = history.inFlight.map((each) => each.url);
  expect(flying.some((url) => /\/history-never-answered$/.test(url))).toBe(true);
  expect(flying.some((url) => /\/history-refused$/.test(url))).toBe(false);
  expect(history.inFlight.every((each) => each.ageMs >= 0)).toBe(true);
  expect(history.request.every((each) => typeof each.at === 'number' && each.method === 'GET')).toBe(true);
  expect(Object.keys(history).sort()).toEqual(['console', 'inFlight', 'note', 'pageerror', 'request', 'requestfailed', 'requestfinished']);
});

test('a very long console message, error and URL are kept as their first 300 characters, each a copy (#575)', async ({ page }) => {
  const history = keepHistory(page);
  await page.route('**/long-url/**', (route) => route.fulfill({ body: 'ok' }));
  const longUrl = `http://history.test/long-url/${'u'.repeat(1_000_000)}`;
  await page.setContent('<!doctype html><title>Long</title><p>Long</p>');
  await page.evaluate((url) => {
    console.log('c'.repeat(1_000_000));
    setTimeout(() => { throw new Error('e'.repeat(1_000_000)); }, 0);
    fetch(url).catch(() => {});
  }, longUrl);
  await expect.poll(() => {
    const snap = history.snapshot();
    return snap.console.length + snap.pageerror.length + snap.requestfinished.length;
  }).toBe(3);
  const snap = history.snapshot();
  expect(snap.console[0].text).toBe('c'.repeat(300));
  expect(snap.pageerror[0].message).toBe('e'.repeat(300));
  expect(snap.requestfinished[0].url).toBe(longUrl.slice(0, 300));
});

test('the history takes its listeners off when its page closes (#575)', async ({ browser }) => {
  const events = ['console', 'pageerror', 'request', 'requestfinished', 'requestfailed', 'close'];
  const listeners = (page) => events.reduce((count, event) => count + page.listenerCount(event), 0);
  const other = await browser.newPage();
  const before = listeners(other);
  keepHistory(other);
  expect(listeners(other)).toBe(before + 6);
  // Playwright clears a closed page's listeners itself, so the page's off calls are recorded instead
  const removed = [];
  const off = other.off.bind(other);
  other.off = (event, listener) => { removed.push(event); return off(event, listener); };
  other.emit('close');
  expect([...new Set(removed)].sort()).toEqual(['console', 'pageerror', 'request', 'requestfailed', 'requestfinished']);
  await other.close();
});

test('a page busy for 12 s that then recovers is captured, not attached to, and runs on', async ({ page, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  await page.setContent('<!doctype html><title>Busy</title>');
  const session = await stallWatch.session(page);
  // heavy layout, a loaded runner: a synchronous task that ends by itself
  await session.send('Runtime.evaluate', { expression: 'setTimeout(() => { const end = Date.now() + 12000; while (Date.now() < end); }, 0)' });
  const capture = await stallWatch.next(page, 30000);
  expect(capture.answers.task.answered, 'the task came after the busy time or not at all').toBe(false);
  expectBusyNotFrozen(capture);
  await expect.poll(() => page.evaluate(() => 1 + 1), { timeout: 30000 }).toBe(2);
});

test('a renderer that is frozen (no CPU, no answer) has its native stacks captured', async ({ page, browser, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  test.setTimeout(testInfo.timeout + NATIVE_MOST_MS);
  await page.setContent('<!doctype html><title>Frozen</title><p>Frozen</p>');
  const pids = await rendererPids(browser);
  expect(pids.length).toBeGreaterThan(0);
  const capture = await frozen(pids, () => stallWatch.next(page, 20000 + NATIVE_MOST_MS));
  expect(capture.reason).toContain('did not answer');
  expect(capture.answers.task.answered).toBe(false);
  expect(Math.max(...capture.rendererCpu.map((process) => process.cpuSeconds))).toBeLessThan(FROZEN_CPU_SECONDS);
  expectNativeStacks(capture, pids);
  expect(capture.kernel.error).toBeUndefined();
  expect(capture.kernel.cgroups.map((each) => each.pid)).toEqual(expect.arrayContaining(pids));
  expect(capture.kernel.kernelLog).toBeTruthy();
  await expect.poll(() => page.evaluate(() => 1 + 1), { timeout: 30000 }).toBe(2);
});

// Keyword: flight recorder (#575). Where the rings run (CI, or QUIRE_FLIGHT=1 for the worker) a frozen
// renderer's capture holds both written out; where they do not it says why, and nothing fails.
test('a frozen renderer\'s capture holds the flight recorder\'s kernel ring and Chrome\'s trace, or says why not (#575)', async ({ page, browser, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  test.setTimeout(testInfo.timeout + NATIVE_MOST_MS);
  await page.setContent('<!doctype html><title>Frozen</title><p>Frozen</p>');
  for (let i = 0; i < 5; i += 1) await page.evaluate(() => 1);
  const pids = await rendererPids(browser);
  const capture = await frozen(pids, () => stallWatch.next(page, 20000 + NATIVE_MOST_MS));
  expect(capture.test, 'the capture names its test (G6 of #575)').toBe(testInfo.title);
  expect(capture.pageAgeMs, 'and the page\'s age at the capture, armed after (G5)').toBeGreaterThan(0);
  expect(capture.armedAfterMs).toBeGreaterThanOrEqual(0);
  expect(capture.flight, 'a frozen renderer\'s capture has the flight recorder\'s record').toBeTruthy();
  expect(capture.flight.error).toBeUndefined();
  for (const [name, ring] of [['kernel', capture.flight.kernel], ['browserTrace', capture.flight.browserTrace]]) {
    if (!wanted()) { expect(ring.unavailable, `${name} says it is not recording`).toMatch(/not recording/); continue; }
    if (ring.unavailable || ring.error) { expect(`${ring.unavailable || ring.error}`, `${name} says why it cannot`).toMatch(/\w{4}/); continue; }
    expect(ring.bytes, `${name} ring has content`).toBeGreaterThan(100);
  }
  if (capture.flight.kernel.file) {
    const seen = await ringSeen(capture.flight.kernel.file, { futex: /sys_futex/, wakeup: /sched_wakeup/ });
    expect(seen.futex, 'the kernel ring holds the run\'s futex calls').not.toBeNull();
    expect(seen.wakeup, 'and its wakeups').not.toBeNull();
  }
  if (capture.flight.browserTrace.file) {
    const trace = JSON.parse(gunzipSync(readFileSync(capture.flight.browserTrace.file)).toString());
    const events = trace.traceEvents || trace;
    expect(events.length, 'Chrome\'s trace holds events').toBeGreaterThan(100);
    expect(new Set(events.map((event) => event.cat)).size, 'of more than one category').toBeGreaterThan(1);
  }
  expect(summary(capture)).toContain('flight kernel ring');
  await expect.poll(() => page.evaluate(() => 1 + 1), { timeout: 30000 }).toBe(2);
});

test('the kernel ring starts for a process tree, keeps its futex calls and wakeups, and is removed (#575)', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const env = { CI: 'true' };
  const started = await startKernel(env);
  if (!started.instance) {
    // no tracefs, or sudo refused: said, not failed
    expect(started.error, 'the ring says why it did not start').toMatch(/\w{4}/);
    return;
  }
  try {
    expect(env.QUIRE_FLIGHT_INSTANCE).toBe(started.instance);
    // this process is the tree's root: its own waits and wakeups are the record (a worker's message is both)
    await page_free_work();
    const out = testInfo.outputPath('kernel.txt.gz');
    const kept = await keepKernel(out, env);
    expect(kept.error, JSON.stringify(kept)).toBeUndefined();
    expect(kept.lines).toBeGreaterThan(0);
    const seen = await ringSeen(out, { header: /# the last/, events: /sys_futex|sched_switch|sched_wakeup/, clock: /clock: mono/ });
    expect(seen.header).not.toBeNull();
    expect(seen.events).not.toBeNull();
    expect(seen.clock, 'timestamps are CLOCK_MONOTONIC (the clock of Chrome\'s trace)').not.toBeNull();
  } finally {
    const stopped = await stopKernel(started);
    expect(stopped.removed, JSON.stringify(stopped)).toBe(true);
  }
});

// a little work in this process: timers and a worker thread's messages are futex waits and wakes
async function page_free_work() {
  const { Worker } = await import('node:worker_threads');
  const worker = new Worker('require("worker_threads").parentPort.postMessage(1)', { eval: true });
  await new Promise((resolve) => worker.once('message', resolve));
  await worker.terminate();
}

test('with neither CI nor QUIRE_FLIGHT, or with QUIRE_NO_RECORDER, nothing is recorded and the capture says so (#575)', async ({ browser }, testInfo) => {
  desktopOnly(testInfo);
  for (const env of [{}, { CI: 'true', QUIRE_NO_RECORDER: '1' }, { QUIRE_FLIGHT: '1', QUIRE_NO_RECORDER: '1' }]) {
    expect(wanted(env), JSON.stringify(env)).toBe(false);
    expect(await startKernel(env)).toBeNull();
    expect((await keepKernel(testInfo.outputPath('x.gz'), env)).unavailable).toMatch(/not recording/);
  }
  expect(wanted({ CI: 'true' })).toBe(process.platform === 'linux');
  expect(wanted({ QUIRE_FLIGHT: '1' })).toBe(process.platform === 'linux');
  expect(wanted({ CI: '0' })).toBe(false);
  expect(startBrowserTrace(browser, {})).toBeNull();
});

test('the run of the @serial tests is told from the other by its command line, as gen-pwa passes it (#575)', async ({}, testInfo) => {
  desktopOnly(testInfo);
  expect(serialRun(['node', 'playwright', 'test', '--project=x', '--grep', '@serial', 'e2e/a.spec.js'])).toBe(true);
  expect(serialRun(['test', '--grep=@serial'])).toBe(true);
  expect(serialRun(['test', '-g', '@serial'])).toBe(true);
  expect(serialRun(['test', '--grep-invert', '@serial'])).toBe(false);
  expect(serialRun(['test', '--grep-invert=@serial'])).toBe(false);
  expect(serialRun(['test', '--grep', 'dictionary'])).toBe(false);
  expect(serialRun(['test'])).toBe(false);
  expect(serialRun(['test', '--grep'])).toBe(false);
});

/**
 * A page of a context made with QUIRE_NO_STALL_ARM=1, so it is not armed, in a
 * renderer of its own: { context, page, pids, restore }.
 */
async function unarmedPage(browser) {
  const kept = process.env.QUIRE_NO_STALL_ARM;
  const restore = () => { if (kept === undefined) delete process.env.QUIRE_NO_STALL_ARM; else process.env.QUIRE_NO_STALL_ARM = kept; };
  process.env.QUIRE_NO_STALL_ARM = '1';
  try {
    const before = await rendererPids(browser);
    const context = await browser.newContext();   // watched at once, armed (or not) as its page is made
    const page = await context.newPage();
    await page.setContent('<!doctype html><title>Unarmed</title><p>Unarmed</p>');
    const pids = (await rendererPids(browser)).filter((pid) => !before.includes(pid));
    expect(pids.length).toBe(1);
    return { context, page, pids, restore };
  } finally {
    restore();
  }
}

test('without gdb the capture of a frozen renderer says so and carries on', async ({ page, browser, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  test.setTimeout(testInfo.timeout + NATIVE_MOST_MS);
  const kept = process.env.QUIRE_STALL_GDB;
  process.env.QUIRE_STALL_GDB = '/nonexistent/gdb';
  try {
    await page.setContent('<!doctype html><title>Frozen</title><p>Frozen</p>');
    const pids = await rendererPids(browser);
    const capture = await frozen(pids, () => stallWatch.next(page, 20000 + NATIVE_MOST_MS));
    expect(capture.native.unavailable).toMatch(/^native capture unavailable: gdb is not installed/);
    // the rest of the capture is what it is without the native side
    expect(capture.answers.task.answered).toBe(false);
    expect(capture.rendererCpu.length).toBeGreaterThan(0);
    expect(capture.verdict).toContain('blocked');
    expect(capture.native.renderers.every((renderer) => renderer.exe && renderer.kernel.tasks.length > 0 && !renderer.gdbStacks.ok)).toBe(true);
    // the fallback tools were asked in order; what none could give is said, with a reason
    for (const renderer of capture.native.renderers) {
      expect(renderer.fallbackStacks.tried.map((each) => each.tool)).toEqual(expect.arrayContaining(['eu-stack']));
      expect(renderer.userSpaceStacks).toMatch(/^(eu-stack|pstack|not available: .+)$/);
      for (const each of renderer.fallbackStacks.tried) if (!each.ok) expect(each.note).toMatch(/^not available: /);
      // one stack per kernel thread at most
      if (renderer.userSpaceStacks === 'eu-stack') {
        const text = renderer.fallbackStacks.tried.find((each) => each.ok).text;
        const blocks = text.match(/^TID \d+:/mg) || [];
        expect(blocks.length, `eu-stack gave ${blocks.length} thread blocks for ${renderer.kernel.tasks.length} kernel threads`).toBeLessThanOrEqual(renderer.kernel.tasks.length);
        expect(blocks, 'the main thread (TID = pid) has a block').toContain(`TID ${renderer.pid}:`);
        expect(text).toMatch(/^#0\s+0x[0-9a-f]+ \S+/m);
      }
    }
  } finally {
    if (kept === undefined) delete process.env.QUIRE_STALL_GDB; else process.env.QUIRE_STALL_GDB = kept;
  }
});

/** A directory with an executable stand-in for a stack tool, first on PATH while `during` runs. */
async function withTools(tools, during) {
  const directory = mkdtempSync(join(tmpdir(), 'stack-tool-stubs-'));
  const kept = process.env.PATH;
  try {
    for (const [name, script] of Object.entries(tools)) { writeFileSync(join(directory, name), `#!/bin/sh\n${script}\n`); chmodSync(join(directory, name), 0o755); }
    process.env.PATH = `${directory}${delimiter}${kept}`;
    return await during();
  } finally {
    process.env.PATH = kept;
    rmSync(directory, { recursive: true, force: true });
  }
}

const NO_GDB = '/nonexistent/gdb';

test('without gdb the stacks come from eu-stack, else pstack, else the capture says why none can', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const hung = spawn('sleep', ['300'], { stdio: 'ignore' });
  const kept = process.env.QUIRE_STALL_GDB;
  process.env.QUIRE_STALL_GDB = NO_GDB;
  try {
    await started(hung);   // the program is running, not on its way to it
    const FRAMES = 'echo "PID $2 - process"; echo "TID $2:"; echo "#0  0x00007f0000001000 - /lib/libc.so.6 + 0x1000 nanosleep"; echo "#1  0x0000555500002000 - /usr/bin/sleep + 0x2000 main"';
    // eu-stack answers: it is used, pstack is not asked
    const first = await withTools({ 'eu-stack': FRAMES, pstack: 'echo "#0 pstack should not run"' }, () => nativeStacks([{ pid: hung.pid }], nativeScope()));
    expect(first.renderers[0].userSpaceStacks).toBe('eu-stack');
    expect(first.renderers[0].fallbackStacks.tried.map((each) => each.tool)).toEqual(['eu-stack']);
    expect(first.renderers[0].fallbackStacks.tried[0].text).toContain('nanosleep');
    // eu-stack fails (ptrace refused), pstack answers
    const second = await withTools({ 'eu-stack': 'echo "eu-stack: cannot attach to process: Operation not permitted" >&2; exit 1', pstack: 'echo "#0  0x00007f0000001000 in nanosleep ()"' }, () => nativeStacks([{ pid: hung.pid }], nativeScope()));
    expect(second.renderers[0].userSpaceStacks).toBe('pstack');
    const [failed, answered] = second.renderers[0].fallbackStacks.tried;
    expect(failed.ok).toBe(false);
    expect(failed.note).toMatch(/^not available: eu-stack gave no stacks: .*Operation not permitted/);
    expect(answered.ok).toBe(true);
    // both fail: the entry says why, and nothing throws
    const third = await withTools({ 'eu-stack': 'exit 3', pstack: 'echo nothing to show' }, () => nativeStacks([{ pid: hung.pid }], nativeScope()));
    expect(third.error).toBeUndefined();
    expect(third.renderers[0].userSpaceStacks).toMatch(/^not available: gdb \(gdb is not installed\); not available: eu-stack gave no stacks.*; not available: pstack gave no stacks/);
    // the kernel's view and the maps are there whatever the tools said
    expect(third.renderers[0].kernel.tasks.length).toBeGreaterThan(0);
    expect(third.renderers[0].mapsError).toBeUndefined();
    expect(third.renderers[0].modules.length).toBeGreaterThan(0);
  } finally {
    hung.kill('SIGKILL');
    if (kept === undefined) delete process.env.QUIRE_STALL_GDB; else process.env.QUIRE_STALL_GDB = kept;
  }
});

/** Whether this machine has the tool: the tests of the real ones skip, saying so, where it does not. */
const installed = (tool) => whichExecutable(tool) !== null;

test('a stack tool that prints frames and exits 1, or prints pstack\'s lines, has given its stacks', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const hung = spawn('sleep', ['300'], { stdio: 'ignore' });
  const kept = process.env.QUIRE_STALL_GDB;
  process.env.QUIRE_STALL_GDB = NO_GDB;
  try {
    await started(hung);   // the program is running, not on its way to it
    const UNWOUND = 'echo "TID $2:"; echo "#0  0x00007f0000001000 nanosleep - /lib/libc.so.6"; echo "eu-stack: tid 9: no matching address range" >&2; exit 1';
    const partial = await withTools({ 'eu-stack': UNWOUND, pstack: 'echo "#0 pstack should not run"' }, () => nativeStacks([{ pid: hung.pid }], nativeScope()));
    expect(partial.renderers[0].userSpaceStacks, 'frames with exit code 1 are stacks').toBe('eu-stack');
    expect(partial.renderers[0].fallbackStacks.tried[0].exitCode).toBe(1);
    const PSTACK = 'echo ""; echo "$1: sleep 300"; echo "(No symbols found)"; echo "0x7effb28ecb7a: ????"; echo "0x7effb28f9b27: ???? (c000, 100000010600000) + 60"';
    const lines = await withTools({ 'eu-stack': 'exit 3', pstack: PSTACK }, () => nativeStacks([{ pid: hung.pid }], nativeScope()));
    expect(lines.renderers[0].userSpaceStacks, 'pstack\'s own frame lines are stacks').toBe('pstack');
    const none = await withTools({ 'eu-stack': 'exit 3', pstack: 'echo "(No symbols found)"; echo "ptrace: Input/output error can\'t read target." >&2; exit 1' }, () => nativeStacks([{ pid: hung.pid }], nativeScope()));
    expect(none.renderers[0].userSpaceStacks).toMatch(/^not available: gdb .*pstack gave no stacks: ptrace: Input\/output error/);
  } finally {
    hung.kill('SIGKILL');
    if (kept === undefined) delete process.env.QUIRE_STALL_GDB; else process.env.QUIRE_STALL_GDB = kept;
  }
});

test('the real eu-stack and pstack give the stacks of a hung process when gdb does not', async ({}, testInfo) => {
  desktopOnly(testInfo);
  test.skip(!installed('eu-stack') || !installed('pstack'), 'eu-stack (elfutils) and pstack are not both installed on this machine');
  const hung = spawn('sleep', ['300'], { stdio: 'ignore' });
  const kept = process.env.QUIRE_STALL_GDB;
  process.env.QUIRE_STALL_GDB = NO_GDB;
  try {
    await started(hung);   // the program is running, not on its way to it
    const real = await nativeStacks([{ pid: hung.pid }], nativeScope());
    if (real.renderers[0].userSpaceStacks.startsWith('not available') && CANNOT_ATTACH.test(real.renderers[0].fallbackStacks.tried.map((each) => each.stderr).join('\n'))) unavailable('the kernel does not let this user attach');
    expect(real.renderers[0].userSpaceStacks).toBe('eu-stack');
    expect(real.renderers[0].fallbackStacks.tried[0].text).toMatch(/^#0\s+0x[0-9a-f]+ \S*nanosleep/m);
    const handed = await withTools({ 'eu-stack': 'exit 3' }, () => nativeStacks([{ pid: hung.pid }], nativeScope()));
    expect(handed.renderers[0].userSpaceStacks).toBe('pstack');
    expect(handed.renderers[0].fallbackStacks.tried[1].text).toMatch(/^0x[0-9a-f]+: /m);
  } finally {
    hung.kill('SIGKILL');
    if (kept === undefined) delete process.env.QUIRE_STALL_GDB; else process.env.QUIRE_STALL_GDB = kept;
  }
});

test('the browser and GPU processes are asked for their stacks by the fallback tools, and a utility process is not (#575)', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const hung = spawn('sleep', ['300'], { stdio: 'ignore' });
  const browser = spawn('sleep', ['300'], { stdio: 'ignore' });
  const gpu = spawn('sleep', ['300'], { stdio: 'ignore' });
  const utility = spawn('sleep', ['300'], { stdio: 'ignore' });
  const kept = process.env.QUIRE_STALL_GDB;
  process.env.QUIRE_STALL_GDB = NO_GDB;
  try {
    await started(utility);   // the program is running, not on its way to it
    const FRAMES = 'echo "TID $2:"; echo "#0  0x00007f0000001000 nanosleep - /lib/libc.so.6"; echo "#1  0x0000555500002000 main - /usr/bin/sleep"';
    const others = [
      { pid: browser.pid, type: 'browser', cpuSeconds: 0 },
      { pid: gpu.pid, type: 'GPU', cpuSeconds: 0 },
      { pid: utility.pid, type: 'utility', cpuSeconds: 0 },
    ];
    const found = await withTools({ 'eu-stack': FRAMES, pstack: 'echo "#0 pstack should not run"' }, () => nativeStacks([{ pid: hung.pid }], nativeScope(), null, others));
    const entry = (pid) => found.browserProcesses.find((each) => each.pid === pid);
    expect(found.renderers[0].userSpaceStacks).toBe('eu-stack');
    expect(entry(browser.pid).userSpaceStacks, 'the browser process: eu-stack answered').toBe('eu-stack');
    expect(entry(gpu.pid).userSpaceStacks, 'the GPU process: eu-stack answered').toBe('eu-stack');
    expect(entry(gpu.pid).fallbackStacks.tried.map((each) => each.tool)).toEqual(['eu-stack']);
    expect(entry(gpu.pid).fallbackStacks.tried[0].text).toContain('nanosleep');
    expect(entry(utility.pid).userSpaceStacks, 'a utility process is not asked').toBeUndefined();
    expect(entry(utility.pid).fallbackStacks).toBeUndefined();
    const none = await withTools({ 'eu-stack': 'exit 3', pstack: 'echo nothing to show' }, () => nativeStacks([], nativeScope(), null, others.slice(0, 1)));
    expect(none.error).toBeUndefined();
    expect(none.browserProcesses[0].userSpaceStacks).toMatch(/^not available: eu-stack gave no stacks.*; not available: pstack gave no stacks/);
  } finally {
    hung.kill('SIGKILL');
    browser.kill('SIGKILL');
    gpu.kill('SIGKILL');
    utility.kill('SIGKILL');
    if (kept === undefined) delete process.env.QUIRE_STALL_GDB; else process.env.QUIRE_STALL_GDB = kept;
  }
});

test('the real eu-stack gives a browser or GPU process\'s stacks, and leaves the process running (#575)', async ({}, testInfo) => {
  desktopOnly(testInfo);
  test.skip(!installed('eu-stack'), 'eu-stack (elfutils) is not installed on this machine');
  const browser = spawn('sleep', ['300'], { stdio: 'ignore' });
  const gpu = spawn('sleep', ['300'], { stdio: 'ignore' });
  const kept = process.env.QUIRE_STALL_GDB;
  process.env.QUIRE_STALL_GDB = NO_GDB;
  try {
    await started(gpu);   // the program is running, not on its way to it
    const found = await nativeStacks([], nativeScope(), null, [{ pid: browser.pid, type: 'browser', cpuSeconds: 0 }, { pid: gpu.pid, type: 'GPU', cpuSeconds: 0 }]);
    expect(found.browserProcesses.length).toBe(2);
    for (const other of found.browserProcesses) {
      if (other.userSpaceStacks.startsWith('not available') && CANNOT_ATTACH.test(other.fallbackStacks.tried.map((each) => each.stderr).join('\n'))) unavailable('the kernel does not let this user attach');
      expect(other.userSpaceStacks).toBe('eu-stack');
      expect(other.fallbackStacks.tried[0].text).toMatch(/^#0\s+0x[0-9a-f]+ \S*nanosleep/m);
      expect(stateOf(other.pid), 'the process is left running, not stopped').toMatch(/^[SR]$/);
    }
  } finally {
    browser.kill('SIGKILL');
    gpu.kill('SIGKILL');
    if (kept === undefined) delete process.env.QUIRE_STALL_GDB; else process.env.QUIRE_STALL_GDB = kept;
  }
});

test('a renderer\'s cgroup files and the kernel\'s log lines are read, and say why when they cannot be (#575)', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const root = mkdtempSync(join(tmpdir(), 'stall-cgroup-'));
  const kept = process.env.PATH;
  try {
    const procRoot = join(root, 'proc');
    const cgroupRoot = join(root, 'cgroup');
    const directory = join(cgroupRoot, 'user.slice', 'renderer.scope');
    mkdirSync(directory, { recursive: true });
    mkdirSync(join(procRoot, '4242'), { recursive: true });
    writeFileSync(join(procRoot, '4242', 'cgroup'), '0::/user.slice/renderer.scope\n');
    writeFileSync(join(directory, 'memory.events'), 'low 0\nhigh 0\nmax 0\noom 1\noom_kill 1\n');
    writeFileSync(join(directory, 'memory.current'), '123456\n');
    writeFileSync(join(directory, 'cpu.stat'), `usage_usec 9\nnr_throttled 3\nthrottled_usec 700\n${'x'.repeat(READ_MOST)}`);
    writeFileSync(join(directory, 'cgroup.freeze'), '1\n');
    const found = cgroupEvidence(4242, { proc: procRoot, cgroup: cgroupRoot });
    expect(found.path).toBe('/user.slice/renderer.scope');
    expect(found.files['memory.events']).toContain('oom_kill 1');
    expect(found.files['memory.current']).toBe('123456');
    expect(found.files['cgroup.freeze']).toBe('1');
    expect(found.files['memory.max']).toMatch(/^unavailable: ENOENT/);
    expect(found.files['cpu.stat'].length, 'a file is read to READ_MOST bytes at most').toBeLessThanOrEqual(READ_MOST);
    mkdirSync(join(procRoot, '4243'), { recursive: true });
    writeFileSync(join(procRoot, '4243', 'cgroup'), '1:cpu:/\n');
    expect(cgroupEvidence(4243, { proc: procRoot, cgroup: cgroupRoot }).unavailable).toMatch(/^unavailable: no cgroup v2 line/);
    expect(cgroupEvidence(4244, { proc: procRoot, cgroup: cgroupRoot }).unavailable).toMatch(/^unavailable: \/proc\/4244\/cgroup: ENOENT/);
    const real = cgroupEvidence(process.pid);
    expect(real.unavailable || typeof real.path, 'the real cgroup is read or its reason is said').toBeTruthy();
    if (!real.unavailable) for (const value of Object.values(real.files)) expect(typeof value).toBe('string');
    const logFile = join(root, 'dmesg.txt');
    writeFileSync(logFile, [
      ...Array.from({ length: 230 }, (_, index) => `[${index}.0] Out of memory: Killed process ${index} (renderer)`),
      '[300.0] an ordinary line',
      '[301.0] INFO: task x:9 blocked for more than 120 seconds.',
      '',
    ].join('\n'));
    const log = await withTools({ dmesg: `cat ${logFile}` }, () => kernelLog(nativeScope()));
    if (log.unavailable) unavailable(log.unavailable);
    expect(log.matched).toBe(231);
    expect(log.lines.length).toBe(KERNEL_LOG_LINES);
    expect(log.lines[0]).toContain('Killed process 31 ');
    expect(log.lines.at(-1)).toContain('blocked for more than 120 seconds');
    const realLog = await kernelLog(nativeScope());
    expect(realLog.unavailable || Array.isArray(realLog.lines), 'the real kernel log is read or its reason is said').toBeTruthy();
  } finally {
    process.env.PATH = kept;
    rmSync(root, { recursive: true, force: true });
  }
});

test('a hung stand-in process is read through the same path: its library frames are named', async ({}, testInfo) => {
  desktopOnly(testInfo);
  // a process that is hung for good (it sleeps), in the same sudo and gdb path as a renderer
  const hung = spawn('sleep', ['300'], { stdio: 'ignore' });
  try {
    await started(hung);   // the program is running, not on its way to it
    const found = await nativeStacks([{ pid: hung.pid }], nativeScope());
    if (found.unavailable) unavailable(found.unavailable);
    const stacks = found.renderers[0].gdbStacks;
    if (!stacks.ok && CANNOT_ATTACH.test(`${stacks.stderr}\n${stacks.text}\n${stacks.error}`)) unavailable(`gdb cannot attach on this machine: ${stacks.stderr}`);
    expect(stacks.ok, `${stacks.error} ${stacks.stderr}`).toBe(true);
    expectLibraryFramesNamed(stacks.mainThread.frames);
    expect(stacks.mainThread.frames[0].text, 'the first frame is the sleep').toMatch(/nanosleep/);
  } finally {
    hung.kill('SIGKILL');
  }
});

test('the core of a really hung renderer is bounded, kept compressed and opens in gdb with the stack the capture gave', async ({ page, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  test.setTimeout(testInfo.timeout + NATIVE_MOST_MS);
  // the hang the real freeze is (idle, no answer, an untimed futex wait; seen on a hosted runner as the
  // runner user through sudo: gdb stopped it 0.7 s, a 758 MB core, 15 MB gzipped), not a SIGSTOP (no core of that)
  const hung = await hangPage(page, stallWatch);
  let capture;
  try {
    capture = await stallWatch.next(page, 30000 + NATIVE_MOST_MS);
  } finally {
    hung.release();
  }
  expect(capture.answers.task.answered).toBe(false);
  expect(capture.presumedBusy).toBeUndefined();
  if (capture.native.unavailable) unavailable(capture.native.unavailable);
  const renderer = capture.native.renderers.find((each) => each.gdbStacks && each.core);
  expect(renderer, 'a renderer has native stacks and a core to say').toBeTruthy();
  if (!renderer.gdbStacks.ok && CANNOT_ATTACH.test(`${renderer.gdbStacks.stderr}\n${renderer.gdbStacks.text}\n${renderer.gdbStacks.error}`)) unavailable(`gdb cannot attach on this machine: ${renderer.gdbStacks.stderr}`);
  expect(renderer.gdbStacks.ok).toBe(true);
  // a core not kept (no prlimit, a call that could not run, a cap, the disk) is the machine's, not the
  // code's: the test says so and skips
  if (!renderer.core.kept) unavailable(`no core was kept on this machine: ${JSON.stringify(renderer.core)}`);
  expect(renderer.core.bytes).toBeLessThanOrEqual(CORE_MAX_BYTES);
  expect(renderer.core.gzBytes).toBeLessThanOrEqual(CORE_GZ_MAX_BYTES);
  const coreFacts = `${renderer.core.bytes} bytes, ${renderer.core.gzBytes} gzipped, gdb stopped the renderer ${renderer.gdbStacks.ms} ms, gzip ${renderer.core.gzipMs} ms`;
  testInfo.annotations.push({ type: 'core', description: coreFacts });
  console.error(`[stall-core] ${coreFacts}`);
  // the core opens later with the binary it names, its thread 1 is the process's main thread (the pid is
  // its LWP), and it gives the stack the live gdb gave
  const raw = testInfo.outputPath('opened.core');
  const unpacked = spawnSync('sh', ['-c', 'gzip -dc "$1" > "$2"', 'sh', renderer.core.file, raw], { timeout: 300000 });
  expect(unpacked.status).toBe(0);
  const opened = spawnSync('gdb', ['-batch', '-nx', '-q', '-iex', 'set debuginfod enabled off', '-ex', 'thread 1', '-ex', 'info threads', '-ex', 'bt 3', renderer.exe, raw], { encoding: 'utf8', timeout: 300000 });
  unlinkSync(raw);
  expect(opened.stdout + opened.stderr).toContain('#0');
  expect(opened.stdout, 'thread 1 of the core is the main thread').toMatch(new RegExp(`\\* 1\\s+Thread \\S+ \\(LWP ${renderer.pid}\\)`));
  const live = renderer.gdbStacks.mainThread.frames[0].pc;
  expect(opened.stdout, 'the core\'s main thread is where the live one was').toContain(live.replace(/^0x0*/, ''));
  await expect.poll(() => page.evaluate(() => 1 + 1), { timeout: 30000 }).toBe(2);
});

test('an unarmed page that is busy is judged as an armed one: no native stacks', async ({ browser, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  const { context, page } = await unarmedPage(browser);
  try {
    // a loop through a session of the test's own, since the watch has none for it
    const busy = await context.newCDPSession(page);
    await busy.send('Runtime.evaluate', { expression: 'setTimeout(() => { const end = Date.now() + 12000; while (Date.now() < end); }, 0)' });
    const capture = await stallWatch.next(page, 30000);
    expect(capture.armed).toBe(false);
    expect(capture.evaluate.answered, 'asked with an evaluate of its own').toBe(false);
    expectBusyNotFrozen(capture);
    await expect.poll(() => page.evaluate(() => 1 + 1), { timeout: 30000 }).toBe(2);
  } finally {
    await context.close();
  }
});

test('an unarmed page that is frozen is judged as an armed one: native stacks', async ({ browser, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  test.setTimeout(testInfo.timeout + NATIVE_MOST_MS);
  const { context, page, pids } = await unarmedPage(browser);
  try {
    const capture = await frozen(pids, () => stallWatch.next(page, 20000 + NATIVE_MOST_MS));
    expect(capture.armed).toBe(false);
    expect(capture.evaluate.answered).toBe(false);
    expectNativeStacks(capture, pids);
  } finally {
    for (const pid of pids) { try { process.kill(pid, 'SIGCONT'); } catch (gone) { /* it ended */ } }
    await context.close();
  }
});

/** A second page of the browser in a context of its own, so a renderer of its own: { context, page, pids }. */
async function otherPage(browser, title) {
  const before = await rendererPids(browser);
  const context = await browser.newContext();   // watched at once, like the test's
  const page = await context.newPage();
  await page.setContent(`<!doctype html><title>${title}</title><p>${title}</p>`);
  const pids = (await rendererPids(browser)).filter((pid) => !before.includes(pid));
  expect(pids.length, 'a renderer of its own').toBe(1);
  return { context, page, pids };
}

test('a busy page next to an idle healthy one: nothing is attached, the idle page answers throughout', async ({ page, browser, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  await page.setContent('<!doctype html><title>Busy</title>');
  const other = await otherPage(browser, 'Idle');
  try {
    const session = await stallWatch.session(page);
    await session.send('Runtime.evaluate', { expression: 'setTimeout(() => { const end = Date.now() + 12000; while (Date.now() < end); }, 0)' });
    // the idle page is asked all the while the busy page is captured, and answers every time
    let answered = 0;
    let capture;
    stallWatch.next(page, 30000).then((found) => { capture = found; });
    while (!capture) {
      expect(await other.page.evaluate(() => 1)).toBe(1);
      answered += 1;
      // the questions are the sampler of this test: one every 100 ms, so that the idle page stays idle (keyword: window)
      await lasting(100);
    }
    expect(capture.native, 'the busy page is presumed busy, so no renderer is attached to').toBeUndefined();
    expect(capture.presumedBusy).toContain('presumed busy');
    expect(answered, 'the idle page answered while the busy page was captured').toBeGreaterThan(2);
    const idle = capture.rendererCpu.find((process) => other.pids.includes(process.pid));
    expect(idle.cpuSeconds, 'the other renderer was idle').toBeLessThan(FROZEN_CPU_SECONDS);
    await expect.poll(() => page.evaluate(() => 1 + 1), { timeout: 30000 }).toBe(2);
  } finally {
    await other.context.close();
  }
});

test('a frozen page next to an idle healthy one: every idle renderer is attached to (collateral)', async ({ page, browser, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  test.setTimeout(testInfo.timeout + NATIVE_MOST_MS);
  await page.setContent('<!doctype html><title>Frozen</title><p>Frozen</p>');
  const frozenPids = await rendererPids(browser);
  const other = await otherPage(browser, 'Idle');
  try {
    const capture = await frozen(frozenPids, () => stallWatch.next(page, 20000 + NATIVE_MOST_MS));
    expect(capture.presumedBusy).toBeUndefined();
    expectNativeStacks(capture, frozenPids);
    // documented: the idle page's renderer, whose CPU is as low, is attached to as well
    expect(capture.native.renderers.map((renderer) => renderer.pid)).toContain(other.pids[0]);
  } finally {
    await other.context.close();
  }
});

/**
 * Hangs a page's main thread the way a freeze does, with no SIGSTOP (a group-stopped process can run
 * no call, so it gets no core): a synchronous XHR to a local server that never answers, which leaves
 * the main thread blocked and idle in an untimed wait. { release } lets it go (the request fails).
 */
async function hangPage(page, stallWatch) {
  const held = new Set();
  const server = createServer(() => { /* never answers */ });
  server.on('connection', (socket) => held.add(socket));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  await page.setContent('<!doctype html><title>Hung</title><p>Hung</p>');
  const session = await stallWatch.session(page);
  await session.send('Runtime.evaluate', { expression: `setTimeout(() => { const request = new XMLHttpRequest(); request.open('GET', 'http://127.0.0.1:${port}/never', false); request.send(); }, 0)` });
  return { release() { for (const socket of held) socket.destroy(); server.close(); } };
}

/** The state letter of a process (R, S, T stopped, t traced), or null when it is gone. */
function stateOf(pid) {
  try { const stat = readFileSync(`/proc/${pid}/stat`, 'utf8'); return stat.slice(stat.lastIndexOf(')') + 2, stat.lastIndexOf(')') + 3); } catch (gone) { return null; }
}

test('teardown ends a gdb attached to a hung renderer: gdb lets go and the renderer runs again', async ({ page, browser, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  stallWatch.state.cutOnPurpose = 'whole capture'; // this test ends the whole capture itself (a gdb that stays), before it keeps anything: nothing of it is owed
  test.setTimeout(testInfo.timeout + NATIVE_MOST_MS);
  const real = spawnSync('sh', ['-c', 'command -v gdb'], { encoding: 'utf8' }).stdout.trim();
  if (!real) unavailable('gdb is not installed on this machine');
  // A gdb that is the real one, attached to the renderer, and then stays (a `shell sleep` after its
  // commands), named by QUIRE_STALL_GDB (an absolute path: the capture runs it under sudo, whose PATH is
  // not this process's). A shell script, written here, because it must run as root under sudo's own PATH,
  // where node is not (a runner's node lives under its tool cache) and /bin/sh always is, and no existing
  // program does this: gdb itself has to be attached when the teardown ends it.
  const shim = testInfo.outputPath('staying-gdb');
  mkdirSync(shim, { recursive: true });
  const standIn = `${shim}/gdb`;
  // this test's own number in the stay's command (`sleep <marker>`), so what it looks for and kills is
  // what it started, never another run's or another checkout's
  const marker = 100000 + Math.floor(Math.random() * 899999);
  // The stand-in leaves out the capture's core commands (the madvise calls and generate-core-file): the
  // stay runs after every `-ex`, and a core of a CI renderer took until `timeout -s KILL` ended gdb
  // (run 39716613681: 748 MB written at 32 s), before the stay, so no gdb was left to find (#807, e2e
  // keyword stall-capture). This test is about teardown ending a gdb that is attached; cores have their own tests.
  writeFileSync(standIn, [
    '#!/bin/sh',
    `[ "$1" = --version ] && exec ${real} --version`,
    'remaining=$#',
    'while [ "$remaining" -gt 0 ]; do',
    '  argument=$1; shift; remaining=$((remaining - 1))',
    '  if [ "$argument" = -ex ] && [ "$remaining" -gt 0 ]; then',
    '    command=$1; shift; remaining=$((remaining - 1))',
    '    case "$command" in',
    "      generate-core-file*|'call (int)madvise'*) continue ;;",
    '    esac',
    '    set -- "$@" "$argument" "$command"',
    '  else',
    '    set -- "$@" "$argument"',
    '  fi',
    'done',
    `exec ${real} "$@" -ex 'shell sleep ${marker}'`,
    ''].join('\n'));
  chmodSync(standIn, 0o755);
  const kept = process.env.QUIRE_STALL_GDB;
  const processes = () => spawnSync('ps', ['-eo', 'stat=,args='], { encoding: 'utf8' }).stdout.split('\n').map((line) => line.trim());
  const staying = () => processes().filter((line) => new RegExp(`^[^Z]\\S*\\s+sleep ${marker}$`).test(line)).join('\n');
  // gdb (its command ends in the stay's `shell sleep <marker>`) and the `timeout` that runs the stand-in (its path)
  const gdbRunning = () => processes().filter((line) => /^[^Z]/.test(line) && (line.includes(`shell sleep ${marker}`) || line.includes(standIn))).join('\n');
  process.env.QUIRE_STALL_GDB = standIn;
  let hung;
  try {
    hung = await hangPage(page, stallWatch);
    const pids = await rendererPids(browser);
    // gdb has attached, written the stacks and the core, and stays
    // e2e stall-capture: the native step follows the kernel ring and Chrome's trace, which ended 47.5 s after the hang on a CI
    // runner (run 40081059903, job 120837242373), so a fixed 45 s gave up before gdb started and the finally below put the real
    // gdb back; it waits for the stay, or for the capture to end without one, within the capture's own bound
    const captured = () => !!(stallWatch.captures[0] && stallWatch.captures[0].result);
    await expect.poll(() => !!staying() || captured(), { timeout: NATIVE_MOST_MS, intervals: [250] }).toBe(true);
    if (!staying()) {
      const capture = stallWatch.captures[0] && stallWatch.captures[0].result;
      if (capture && capture.native && capture.native.unavailable) unavailable(capture.native.unavailable);
    }
    expect(staying(), 'gdb is attached to the hung renderer and staying').not.toBe('');
    expect(pids.some((pid) => ['t', 'T'].includes(stateOf(pid))), 'gdb holds the renderer stopped').toBe(true);
    await stallWatch.stop();
    await expect.poll(gdbRunning, { message: 'stop() ended gdb: nothing of the capture left behind', timeout: 3000, intervals: [250] }).toBe('');
    expect(pids.some((pid) => ['t', 'T'].includes(stateOf(pid))), 'no renderer is left stopped').toBe(false);
    // and the renderer works: the request is let go, the main thread returns, the page answers
    hung.release();
    await expect.poll(() => page.evaluate(() => 1 + 1), { timeout: 30000 }).toBe(2);
  } finally {
    if (hung) hung.release();
    spawnSync('pkill', ['-KILL', '-f', `sleep ${marker}`]);
    if (kept === undefined) delete process.env.QUIRE_STALL_GDB; else process.env.QUIRE_STALL_GDB = kept;
  }
});

test('teardown does not wait for a native capture to end: stop() returns within its bound', async ({ page, browser, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  stallWatch.state.cutOnPurpose = 'whole capture'; // the teardown here ends the whole capture, before it keeps anything: nothing of it is owed
  await page.setContent('<!doctype html><title>Frozen</title><p>Frozen</p>');
  const pids = await rendererPids(browser);
  await frozen(pids, async () => {
    await stallWatch.started(page, 30000);
    const started = Date.now();
    await stallWatch.stop();
    // the capture of a frozen page takes longer than this: stop gives it TEARDOWN_MS, then ends its commands
    expect(Date.now() - started).toBeLessThan(TEARDOWN_MOST_MS + 1500);
  });
});

test('the kernel evidence is saved before the native step, which a teardown can cut off (#575)', async ({ page, browser, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  stallWatch.state.cutOnPurpose = 'native step'; // the freeze here is cut off by the teardown on purpose, in the native step: the rings are owed, that step's fields are not
  test.setTimeout(testInfo.timeout + CAPTURE_MOST_MS + NATIVE_MOST_MS);
  await page.setContent('<!doctype html><title>Frozen</title><p>Frozen</p>');
  const armed = await arm(page);
  const pids = await rendererPids(browser);
  const saved = [];
  const result = await frozen(pids, () => capture(page, armed, 'a capture asked for', browser, (partial) => saved.push({ kernel: partial.kernel, native: partial.native })));
  await armed.session.detach().catch(() => {});
  expect(result.native, 'the renderer was frozen, so the native step ran').toBeDefined();
  expect(saved[0].native, 'the first save is before the native step').toBeUndefined();
  expect(saved[0].kernel.cgroups.length).toBeGreaterThan(0);
  expect(saved[saved.length - 1].native).toBeDefined();
});

test('a page that answers is not captured', async ({ page, stallWatch }) => {
  await page.setContent('<!doctype html><title>Idle</title><p>Idle</p>');
  // the watch has probed the page twice and the page answered both: a page that answers is not captured
  await stallWatch.answered(page, 2, 30000);
  expect(stallWatch.captures).toEqual([]);
});

test('QUIRE_NO_STALL_ARM skips arming and nothing else sets it', async ({ page }) => {
  const kept = process.env.QUIRE_NO_STALL_ARM;
  try {
    delete process.env.QUIRE_NO_STALL_ARM;
    const armed = await arm(page);
    expect(armed.error, 'armed by default').toBeNull();
    expect(armed.session).not.toBeNull();
    await armed.session.detach();
    for (const off of ['', '0']) {
      process.env.QUIRE_NO_STALL_ARM = off;
      const stillArmed = await arm(page);
      expect(stillArmed.error, `armed when set to "${off}"`).toBeNull();
      await stillArmed.session.detach();
    }
    process.env.QUIRE_NO_STALL_ARM = '1';
    const listening = ['console', 'pageerror', 'request', 'requestfinished', 'requestfailed'].map((event) => page.listenerCount(event));
    const notArmed = await arm(page);
    expect(['console', 'pageerror', 'request', 'requestfinished', 'requestfailed'].map((event) => page.listenerCount(event)), 'no listener when arming is off').toEqual(listening);
    expect(notArmed.history).toBeNull();
    expect(notArmed.session, 'no DevTools session, so no debugger').toBeNull();
    expect(notArmed.error).toContain('QUIRE_NO_STALL_ARM=1');
  } finally {
    if (kept === undefined) delete process.env.QUIRE_NO_STALL_ARM; else process.env.QUIRE_NO_STALL_ARM = kept;
  }
});

const NEAR_TIMEOUT_MS = 30000;

test('every page of a test about to time out is captured', async ({ page, stallWatch }, testInfo) => {
  // the answering page's capture (CAPTURE_MOST_MS) must end within twice that, once it has begun
  test.setTimeout(NEAR_TIMEOUT_MS);
  await page.setContent('<!doctype html><title>Idle</title><p>Idle</p>');
  await stallWatch.started(page, NEAR_TIMEOUT_MS);
  const headroom = 2 * CAPTURE_MOST_MS;
  test.setTimeout(testInfo.timeout + headroom);
  const capture = await stallWatch.next(page, headroom);
  expect(capture.reason).toBe('test about to time out');
  // nothing runs, so nothing pauses; the profile is taken instead
  expect(capture.paused).toBeUndefined();
  expect(capture.profile.samples).toBeGreaterThan(0);
  expect(capture.answers.task.answered).toBe(true);
  expect(capture.verdict).toContain('free');
  // a page that answers is not stalled: gdb never stops its renderer
  expect(capture.native).toBeUndefined();
  // and the pause it asked for is dropped: the page still runs script
  expect(await page.evaluate(() => 1 + 1)).toBe(2);
});

// ---- the evidence for a page that was slow, not frozen (#600) ----
//
// A test that fails on a page that answered slowly keeps what tells a slow
// runner from a slow page: the runner's load over the last minute
// (runner-load.json), and each helper attempt's duration, why it was tried
// again, DevTools' metrics around it, and the long tasks the page saw
// (page-timing.json). These tests check the fields are there, and that
// taking them never fails or hangs a test.

test('a capture holds the runner\'s load over the last minute and the page\'s attempts', async ({ page, browser, stallWatch }) => {
  await page.setContent('<!doctype html><title>Idle</title><p>Idle</p>');
  const armed = await arm(page);
  // two samples at least, 2 s apart: the sampler has taken them
  await expect.poll(() => runnerLoad(60000).samples.length, { timeout: 30000 }).toBeGreaterThanOrEqual(2);
  const result = await capture(page, armed, 'a capture asked for', browser);
  await armed.session.detach();
  const load = result.runnerLoad;
  expect(typeof load, `runnerLoad is ${JSON.stringify(load).slice(0, 200)}`).toBe('object');
  expect(load.everyMs).toBe(SAMPLE_EVERY_MS);
  expect(load.samples.length).toBeGreaterThan(0);
  for (const field of ['cpuPressureSomeAvg10', 'ioPressureSomeAvg10', 'memoryPressureSomeAvg10', 'stealPercent', 'iowaitPercent', 'idlePercent', 'workerLateMs', 'browserCores']) {
    expect(load.summary, field).toHaveProperty(field);
  }
  expect(load.summary.cores).toBeGreaterThan(0);
  expect(load.summary.reading).toContain('CPU pressure');
  // a source the machine lacks is a note, never a missing field
  for (const each of load.samples) {
    for (const resource of ['cpu', 'io', 'memory']) {
      const pressure = each.pressure[resource];
      expect(typeof pressure === 'string' ? pressure.startsWith('not available: ') : 'some' in pressure, `pressure ${resource}`).toBe(true);
    }
    expect(typeof each.loadAverage).toBe('string');
    expect(each.lateMs).toBeGreaterThanOrEqual(0);
  }
  const later = load.samples.find((each) => each.intervalMs !== null && each.intervalMs !== undefined && typeof each.cpuShare === 'object');
  if (later) for (const name of ['user', 'system', 'idle', 'iowait', 'steal']) expect(typeof later.cpuShare[name], `cpuShare.${name}`).toBe('number');
  // the old fields are as they were
  for (const field of ['reason', 'at', 'url', 'armed', 'rendererCpu', 'machine', 'verdict']) expect(result, field).toHaveProperty(field);
  // the page's timing is in the capture too
  expect(Array.isArray(result.pageTiming.attempts)).toBe(true);
  expect(Array.isArray(result.pageTiming.longTasks)).toBe(true);
  expect(summary(result)).toContain('runner: over the last');
});

test('an attempt is noted with its duration, DevTools metrics and the long tasks the page saw', async ({ page, stallWatch }) => {
  await page.setContent('<!doctype html><title>Busy</title><p>Busy</p>');
  await stallWatch.session(page);
  const log = attemptsOf(page);
  expect(log, 'the watch bound a log to the page').toBeTruthy();
  await attempted(page, 'busy', 1, () => page.evaluate(() => new Promise((done) => setTimeout(() => { const began = performance.now(); while (performance.now() - began < 400); done(); }, 10))), { detail: 'kept' });
  await expect(attempted(page, 'broken', 2, () => { throw new Error('it did not work\nsecond line'); })).rejects.toThrow('it did not work');
  noted(page, 'busy', 3, { why: 'a note' });
  const [busy, broken, note] = log.entries.slice(-3);
  expect(busy).toMatchObject({ step: 'busy', attempt: 1, outcome: 'ok', detail: 'kept' });
  expect(busy.ms).toBeGreaterThanOrEqual(390);
  expect(busy.startedAt).toMatch(/^\d{4}-\d\d-\d\dT/);
  expect(busy.devtools.unavailable, 'the metrics were read').toBeUndefined();
  expect(busy.devtools.taskMs, 'the busy task shows in the main thread\'s task time').toBeGreaterThanOrEqual(300);
  expect(busy.devtools.threadCpuMs).toBeGreaterThan(0);
  expect(busy.devtools.reading).toContain('ran tasks for');
  for (const field of ['scriptMs', 'layoutMs', 'recalcStyleMs', 'processCpuMs', 'layoutCount']) expect(busy.devtools, field).toHaveProperty(field);
  expect(broken).toMatchObject({ step: 'broken', outcome: 'failed', why: 'it did not work' });
  expect(note).toMatchObject({ outcome: 'note', why: 'a note' });
  // the long task of the loop is seen by the page's observer and taken
  await log.harvest();
  const tasks = log.snapshot().longTasks;
  expect(tasks.some((task) => task.ms >= 300), JSON.stringify(tasks)).toBe(true);
  const kept = await stallWatch.evidence();
  expect(kept.pageTiming.some((each) => each.attempts.length >= 3)).toBe(true);
  expect(kept.runnerLoad.summary.samples).toBeGreaterThan(0);
});

test('taking the evidence never fails or hangs a test, and says why when it cannot', async ({ page, stallWatch }) => {
  // no log bound to a page: the work runs as it always did
  expect(await attempted({}, 'plain', 1, async () => 7)).toBe(7);
  noted({}, 'plain', 1, { why: 'nothing to note in' });
  await expect(attempted({}, 'plain', 1, () => { throw new Error('own failure'); })).rejects.toThrow('own failure');
  // metrics that are missing are a note
  expect(metricsBetween(null, {}, 5).unavailable).toMatch(/^not available: /);
  expect(metricsBetween({ unavailable: 'no page' }, {}, 5).unavailable).toBe('not available: no page');
  // a page that is stuck in a loop: the attempt ends, its metrics are given or said to be unavailable, and it all takes seconds
  await startLoopHeard(page, stallWatch);   // the loop is running; the watch captures it only at 5 s
  try {
    const began = Date.now();
    const log = attemptsOf(page);
    await attempted(page, 'stuck', 1, async () => 'done');
    await log.harvest();
    expect(Date.now() - began, 'bounded by the metrics\' and the harvest\'s limits').toBeLessThan(6000);
    const stuck = log.entries.find((each) => each.step === 'stuck');
    expect(stuck.outcome).toBe('ok');
    // Performance.getMetrics may be answered by a busy page (an interrupting command, as
    // Debugger.setBreakpointsActive is) or not; either way the entry says which
    if (stuck.devtools.unavailable) expect(stuck.devtools.unavailable).toMatch(/^not available: /);
    else expect(stuck.devtools.wallMs).toBeGreaterThanOrEqual(0);
    // and the evidence is still given
    const kept = await stallWatch.evidence();
    expect(kept.pageTiming[0].attempts.some((each) => each.step === 'stuck')).toBe(true);
  } finally {
    await endLoop(page, stallWatch);
  }
});

test('a page that answers nothing costs the attempts one wait, not one before and one after each (#715)', async ({ page, stallWatch }) => {
  await startLoopHeard(page, stallWatch);
  try {
    const log = attemptsOf(page);
    const took = [];
    for (let attempt = 1; attempt <= 4; attempt++) {
      const began = Date.now();
      await expect(attempted(page, 'frozen', attempt, () => { throw new Error('the click did not land'); })).rejects.toThrow('did not land');
      took.push(Date.now() - began);
    }
    const entries = log.entries.filter((each) => each.step === 'frozen');
    expect(entries).toHaveLength(4);
    // an attempt that waited for nothing is quick: if the first read timed out, the others were not made
    const timedOut = entries.some((each) => String(each.devtools.unavailable).includes('was not answered'));
    if (timedOut) {
      expect(took.slice(1).every((ms) => ms < 500), `later attempts took ${took}`).toBe(true);
      expect(entries[1].devtools.unavailable).toContain('not asked');
    }
    // the four tries of a page that answers nothing take about one wait in all
    expect(took.reduce((a, b) => a + b, 0), `took ${took}`).toBeLessThan(2500);
  } finally {
    await endLoop(page, stallWatch);
  }
});

test('the runner\'s samples taken under the name of an earlier test remain after that test left (#715)', async ({ page }) => {
  const leave = sampleRunner('an earlier test');
  // the sampler has taken a sample under the name
  await expect.poll(() => runnerLoad(60000).samples.some((each) => each.test === 'an earlier test'), { timeout: 30000 }).toBe(true);
  leave();
  // stallWatch is a user of the sampler too, so the timer runs on; the earlier test's samples must be kept, not dropped with its user: a later sample says no test
  await expect.poll(() => { const taken = runnerLoad(60000).samples; return taken[taken.length - 1].test; }, { timeout: 30000 }).toBe('');
  const samples = runnerLoad(60000).samples;
  expect(samples.some((each) => each.test === 'an earlier test'), 'the earlier test\'s samples are still there').toBe(true);
  expect(samples[samples.length - 1].test, 'and the later ones say no test').toBe('');
});

test('a page that stops answering until a read of it times out, and recovers, gets its metrics again within the probe period, not after DEAF_MS (#715)', async ({ page, browser, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  await page.setContent('<!doctype html><title>Recovers</title>');
  await stallWatch.session(page);
  const log = attemptsOf(page);
  await attempted(page, 'before', 1, async () => 1);
  expect(log.entries.find((each) => each.step === 'before').devtools.unavailable, 'answered while idle').toBeUndefined();
  const pids = await rendererPids(browser);
  // frozen (no answer to anything): the read waits its second and the page is deaf from then on; it is let go as that read ends, long before the 5 s that make the probe capture it
  let released = 0;
  await frozen(pids, async () => {
    // the freeze lasts until the read has timed out (the attempt returns after its METRICS_MS): that is what the page is let go for
    await attempted(page, 'frozen', 1, async () => 1);
    expect(String(log.entries.find((each) => each.step === 'frozen').devtools.unavailable)).toContain('was not answered');
    released = Date.now();
  });
  await expect.poll(async () => {
    await attempted(page, 'after', 1, async () => 1);
    return log.entries.filter((each) => each.step === 'after').pop().devtools.unavailable === undefined;
  }, { timeout: 8000, intervals: [250] }).toBe(true);
  const waited = Date.now() - released;
  // the probe asks every PROBE_EVERY_MS (2 s) and hears the page at once; DEAF_MS alone would have kept it deaf for about 4.5 s after the release
  expect(waited, `metrics came back ${waited} ms after the page did`).toBeLessThan(3500);
});

test('an unarmed page notes its attempts and says the metrics are not available', async ({ page }) => {
  const kept = process.env.QUIRE_NO_STALL_ARM;
  try {
    process.env.QUIRE_NO_STALL_ARM = '1';
    const unarmed = await arm(page);
    const log = attemptsOf(page);
    await attempted(page, 'unarmed', 1, async () => 1);
    const entry = log.entries.find((each) => each.step === 'unarmed');
    expect(entry.devtools.unavailable).toMatch(/^not available: /);
    expect(unarmed.timing.snapshot().notAvailable).toMatch(/^not available: /);
  } finally {
    if (kept === undefined) delete process.env.QUIRE_NO_STALL_ARM; else process.env.QUIRE_NO_STALL_ARM = kept;
  }
});
