/**
 * The stall watch itself (e2e/stall-capture.js, #244): a page that runs
 * an endless loop on purpose, in script and in wasm, is captured by the
 * watch on its own, and the capture names the loop's function. The page
 * is a test page of its own (setContent), not the app.
 *
 * The same capture holds the renderer's native stacks (#575, #591): gdb's
 * backtrace of every thread, the kernel's stack, wait channel and system
 * call of every thread, and what resolves their raw addresses offline.
 * A loop's main thread is busy in JIT code or the binary's, so its
 * backtrace has frames in those; where gdb or ptrace is not there the
 * test says so and skips.
 */

import { test, expect } from './fixtures.js';
import { CAPTURE_MOST_MS, NATIVE_MOST_MS } from './stall-capture.js';

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
 * The renderer that spins, among the native stacks of a capture: the one
 * that used the most CPU in the second the capture watched. Skips the
 * test, saying why, where gdb is not there or ptrace is refused.
 */
function spinningRenderer(capture) {
  expect(capture.native.error).toBeUndefined();
  const { gdb, renderers } = capture.native;
  test.skip(!gdb.available, `gdb is not installed on this machine and could not be installed: ${JSON.stringify(gdb.install)}`);
  const spinning = [...capture.rendererCpu].sort((a, b) => b.cpuSeconds - a.cpuSeconds)[0];
  const renderer = renderers.find((each) => each.pid === spinning.pid);
  expect(renderer, 'the busiest renderer has native stacks').toBeTruthy();
  test.skip(!renderer.gdbStacks.ok && /ptrace|Operation not permitted|Permission denied/i.test(renderer.gdbStacks.stderr + renderer.gdbStacks.text),
    `ptrace is refused on this machine (ptrace_scope ${capture.native.ptraceScope}, root ${capture.native.root}): ${renderer.gdbStacks.stderr}`);
  return renderer;
}

/** What a capture of a loop holds of its renderer's native side (#575, #591). */
function expectNativeStacks(renderer, capture, { reachesBinary }) {
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
  // gdb's backtrace of every thread, and the main thread's frames in script's native side
  const stacks = renderer.gdbStacks;
  expect(stacks.ok, `${stacks.error} ${stacks.stderr}`).toBe(true);
  expect(stacks.threadCount).toBe(renderer.kernel.tasks.length);
  expect(stacks.mainThread, 'gdb listed the main thread (LWP = pid)').toBeTruthy();
  const frames = stacks.mainThread.frames;
  expect(frames.length).toBeGreaterThan(0);
  // every frame address is in a mapping; a loop spins in JIT code or in the binary
  expect(frames[0].module).toBeTruthy();
  expect([renderer.exe, '(anonymous executable memory)']).toContain(frames[0].module);
  // gdb has no unwind information for JIT code and follows frame pointers there:
  // script's frames keep them, so the stack reaches the binary's entry trampoline;
  // wasm's do not, so only its first frame (the address in the loop) is dependable
  if (reachesBinary) {
    expect(frames.some((frame) => frame.module === renderer.exe && /^0x[0-9a-f]+$/.test(frame.offset)),
      'the stack reaches the binary at an offset that resolves offline').toBe(true);
  }
  expect(capture.verdict).toContain('running script');
}

test('a page in an endless script loop is captured in that loop', async ({ page, stallWatch }, testInfo) => {
  test.setTimeout(testInfo.timeout + NATIVE_MOST_MS);
  await startLoop(page, stallWatch, 'setTimeout(spinForever, 0)');
  const capture = await stallWatch.next(page, 20000 + NATIVE_MOST_MS);
  expect(capture.reason).toContain('did not answer');
  expect(capture.answers.interrupt.answered).toBe(true);
  expect(capture.answers.task.answered).toBe(false);
  expect(capture.paused.frames[0].functionName).toBe('spinForever');
  expect(capture.verdict).toContain('spinForever');
  await endLoop(page, stallWatch);
  expectNativeStacks(spinningRenderer(capture), capture, { reachesBinary: true });
});

test('a page in an endless wasm loop is captured in that loop', async ({ page, stallWatch }, testInfo) => {
  test.setTimeout(testInfo.timeout + NATIVE_MOST_MS);
  await startLoop(page, stallWatch, `setTimeout(() => enterWasm(${JSON.stringify(SPIN_MODULE)}), 0)`);
  const capture = await stallWatch.next(page, 20000 + NATIVE_MOST_MS);
  const [inWasm, caller] = capture.paused.frames;
  expect(inWasm.functionName).toContain('spinInWasm');
  expect(inWasm.url).toMatch(/^wasm:\/\//);
  expect(caller.functionName).toBe('enterWasm');
  await endLoop(page, stallWatch);
  expectNativeStacks(spinningRenderer(capture), capture, { reachesBinary: false });
});

test('a page that answers is not captured', async ({ page, stallWatch }) => {
  await page.setContent('<!doctype html><title>Idle</title><p>Idle</p>');
  // longer than a probe's limit, so a page that answers has been probed
  await page.waitForTimeout(7000);
  expect(stallWatch.captures).toEqual([]);
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
