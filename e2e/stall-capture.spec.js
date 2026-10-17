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
 * renderer, armed or not. Where gdb or ptrace is not there a test says so and
 * skips, and on CI (which installs gdb and has sudo) fails instead.
 */

import { chmodSync, mkdirSync, unlinkSync, writeFileSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
import { test, expect } from './fixtures.js';
import { arm, CANNOT_ATTACH, CAPTURE_MOST_MS, CORE_GZ_MAX_BYTES, CORE_MAX_BYTES, FROZEN_CPU_SECONDS, nativeScope, nativeStacks, NATIVE_MOST_MS, TEARDOWN_MOST_MS } from './stall-capture.js';

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
  if (!stacks.ok && CANNOT_ATTACH.test(`${stacks.stderr}\n${stacks.text}`)) {
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
  const main = renderer.kernel.tasks.find((task) => task.tid === renderer.pid);
  expect(main, 'the main thread is a task').toBeTruthy();
  expect(main.state).toMatch(/^[RSDtT]$/);
  for (const task of renderer.kernel.tasks) expect(task.syscall, `the syscall of ${task.comm}`).not.toBe('');
  // gdb's backtrace of every thread
  expect(stacks.ok, `${stacks.error} ${stacks.stderr}`).toBe(true);
  expect(stacks.threadCount).toBe(renderer.kernel.tasks.length);
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
  await expect.poll(() => page.evaluate(() => 1 + 1), { timeout: 30000 }).toBe(2);
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
  } finally {
    if (kept === undefined) delete process.env.QUIRE_STALL_GDB; else process.env.QUIRE_STALL_GDB = kept;
  }
});

test('a hung stand-in process is read through the same path: its library frames are named', async ({}, testInfo) => {
  desktopOnly(testInfo);
  // a process that is hung for good (it sleeps), in the same sudo and gdb path as a renderer
  const hung = spawn('sleep', ['300'], { stdio: 'ignore' });
  try {
    await new Promise((resolve) => setTimeout(resolve, 500));
    const found = await nativeStacks([{ pid: hung.pid }], nativeScope());
    if (found.unavailable) unavailable(found.unavailable);
    const stacks = found.renderers[0].gdbStacks;
    if (!stacks.ok && CANNOT_ATTACH.test(`${stacks.stderr}\n${stacks.text}`)) unavailable(`gdb cannot attach on this machine: ${stacks.stderr}`);
    expect(stacks.ok, `${stacks.error} ${stacks.stderr}`).toBe(true);
    expectLibraryFramesNamed(stacks.mainThread.frames);
    expect(stacks.mainThread.frames[0].text, 'the first frame is the sleep').toMatch(/nanosleep/);
  } finally {
    hung.kill('SIGKILL');
  }
});

test('the core of a renderer is bounded, kept compressed and opens in gdb with the stack the capture gave', async ({ page, browser }, testInfo) => {
  desktopOnly(testInfo);
  test.setTimeout(testInfo.timeout + NATIVE_MOST_MS);
  await page.setContent('<!doctype html><title>Core</title><p>Core</p>');
  // an idle renderer, its main thread in the message pump's wait: where a frozen one would be
  const pids = await rendererPids(browser);
  const found = await nativeStacks(pids.map((pid) => ({ pid })), nativeScope(), (pid) => testInfo.outputPath(`stall-core-${pid}.core`));
  if (found.unavailable) unavailable(found.unavailable);
  const renderer = found.renderers[0];
  if (!renderer.gdbStacks.ok && CANNOT_ATTACH.test(`${renderer.gdbStacks.stderr}\n${renderer.gdbStacks.text}`)) unavailable(`gdb cannot attach on this machine: ${renderer.gdbStacks.stderr}`);
  expect(renderer.gdbStacks.ok).toBe(true);
  expect(renderer.core.kept, JSON.stringify(renderer.core)).toBe(true);
  expect(renderer.core.bytes).toBeLessThanOrEqual(CORE_MAX_BYTES);
  expect(renderer.core.gzBytes).toBeLessThanOrEqual(CORE_GZ_MAX_BYTES);
  expect(renderer.gdbStacks.ms, 'the renderer was stopped for the backtraces and the core within gdb\'s limit').toBeLessThan(35000);
  const coreFacts = `${renderer.core.bytes} bytes, ${renderer.core.gzBytes} gzipped, gdb stopped the renderer ${renderer.gdbStacks.ms} ms, gzip ${renderer.core.gzipMs} ms`;
  testInfo.annotations.push({ type: 'core', description: coreFacts });
  console.error(`[stall-core] ${coreFacts}`);
  // the core opens later with the binary it names, and gives the stack the live gdb gave
  const raw = testInfo.outputPath('opened.core');
  const unpacked = spawnSync('sh', ['-c', 'gzip -dc "$1" > "$2"', 'sh', renderer.core.file, raw], { timeout: 60000 });
  expect(unpacked.status).toBe(0);
  const opened = spawnSync('gdb', ['-batch', '-nx', '-q', '-iex', 'set debuginfod enabled off', '-ex', 'thread 1', '-ex', 'bt 3', renderer.exe, raw], { encoding: 'utf8', timeout: 120000 });
  expect(opened.stdout + opened.stderr).toContain('#0');
  unlinkSync(raw);
  const live = renderer.gdbStacks.mainThread.frames[0].pc;
  expect(opened.stdout, 'the core\'s main thread is where the live one was').toContain(live.replace(/^0x0*/, ''));
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
      await new Promise((resolve) => setTimeout(resolve, 100));
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

test('teardown ends a native capture still running: gdb lets go', async ({ page, browser, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  test.setTimeout(testInfo.timeout + NATIVE_MOST_MS);
  // A gdb that answers its version and then hangs, named by QUIRE_STALL_GDB (an absolute path: the
  // capture runs it under sudo, whose PATH is not this process's). A shell script, written here,
  // because it must run as root under sudo's own PATH, where node is not (a runner's node lives
  // under its tool cache), and /bin/sh always is; no existing program hangs on gdb's arguments.
  const shim = testInfo.outputPath('hanging-gdb');
  mkdirSync(shim, { recursive: true });
  const standIn = `${shim}/gdb`;
  writeFileSync(standIn, '#!/bin/sh\n[ "$1" = --version ] && { echo "GNU gdb hanging stand-in"; exit 0; }\nexec sleep 119\n');
  chmodSync(standIn, 0o755);
  const kept = process.env.QUIRE_STALL_GDB;
  // the stand-in's process (a zombie that nobody has reaped yet is gone, only its entry is left)
  const hanging = () => spawnSync('ps', ['-eo', 'stat=,args='], { encoding: 'utf8' }).stdout.split('\n')
    .filter((line) => /^[^Z]\S*\s+sleep 119$/.test(line.trim())).join('\n');
  process.env.QUIRE_STALL_GDB = standIn;
  try {
    await page.setContent('<!doctype html><title>Frozen</title><p>Frozen</p>');
    const pids = await rendererPids(browser);
    await frozen(pids, async () => {
      await stallWatch.started(page, 30000);
      // gdb is started by the capture some seconds after it began: wait for it to be there
      for (let waited = 0; !hanging() && waited < 20000; waited += 250) await new Promise((resolve) => setTimeout(resolve, 250));
      expect(hanging(), 'the stand-in gdb is running, attached to nothing but standing for gdb').not.toBe('');
      await stallWatch.stop();
      for (let waited = 0; hanging() && waited < 3000; waited += 250) await new Promise((resolve) => setTimeout(resolve, 250));
      expect(hanging(), 'stop() ended the command: nothing left behind').toBe('');
    });
  } finally {
    if (kept === undefined) delete process.env.QUIRE_STALL_GDB; else process.env.QUIRE_STALL_GDB = kept;
  }
});

test('teardown does not wait for a native capture to end: stop() returns within its bound', async ({ page, browser, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
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

test('a page that answers is not captured', async ({ page, stallWatch }) => {
  await page.setContent('<!doctype html><title>Idle</title><p>Idle</p>');
  // longer than a probe's limit, so a page that answers has been probed
  await page.waitForTimeout(7000);
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
    const notArmed = await arm(page);
    expect(notArmed.session, 'no DevTools session, so no debugger').toBeNull();
    expect(notArmed.error).toContain('QUIRE_NO_STALL_ARM=1');
  } finally {
    if (kept === undefined) delete process.env.QUIRE_NO_STALL_ARM; else process.env.QUIRE_NO_STALL_ARM = kept;
  }
});

// The timeout this test starts with, short so the capture begins soon
const NEAR_TIMEOUT_MS = 30000;

test('every page of a test about to time out is captured', async ({ page, stallWatch }, testInfo) => {
  // The capture begins TIMEOUT_MARGIN_MS before the timeout (a third of
  // a shorter one), at the watch's next scan: here at 30 s - min(15 s,
  // 30 s / 3) = 20 s, by 20 s + SCAN_EVERY_MS = 21 s on an idle runner.
  // It can then take up to CAPTURE_MOST_MS (25 s), more than the 9 s
  // left, as it can in any test (whose capture is evidence for a test
  // failing anyway). So the test waits for the capture to begin (for as
  // long as its timeout, which bounds that wait anyway), then puts its
  // timeout off by twice CAPTURE_MOST_MS, 50 s, as headroom for a loaded
  // runner, and waits for the capture itself for at most that long.
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
