/**
 * The stall watch itself (e2e/stall-capture.js, #244): a page that runs
 * an endless loop on purpose, in script and in wasm, is captured by the
 * watch on its own, and the capture names the loop's function. The page
 * is a test page of its own (setContent), not the app.
 */

import { test, expect } from './fixtures.js';

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

test('a page in an endless script loop is captured in that loop', async ({ page, stallWatch }) => {
  await startLoop(page, stallWatch, 'setTimeout(spinForever, 0)');
  const capture = await stallWatch.next(page, 20000);
  expect(capture.reason).toContain('did not answer');
  expect(capture.answers.interrupt.answered).toBe(true);
  expect(capture.answers.task.answered).toBe(false);
  expect(capture.paused.frames[0].functionName).toBe('spinForever');
  expect(capture.verdict).toContain('spinForever');
  await endLoop(page, stallWatch);
});

test('a page in an endless wasm loop is captured in that loop', async ({ page, stallWatch }) => {
  await startLoop(page, stallWatch, `setTimeout(() => enterWasm(${JSON.stringify(SPIN_MODULE)}), 0)`);
  const capture = await stallWatch.next(page, 20000);
  const [inWasm, caller] = capture.paused.frames;
  expect(inWasm.functionName).toContain('spinInWasm');
  expect(inWasm.url).toMatch(/^wasm:\/\//);
  expect(caller.functionName).toBe('enterWasm');
  await endLoop(page, stallWatch);
});

test('a page that answers is not captured', async ({ page, stallWatch }) => {
  await page.setContent('<!doctype html><title>Idle</title><p>Idle</p>');
  // longer than a probe's limit, so a page that answers has been probed
  await page.waitForTimeout(7000);
  expect(stallWatch.captures).toEqual([]);
});

test('every page of a test about to time out is captured', async ({ page, stallWatch }) => {
  // a short timeout of its own, so the capture comes soon (15 s before
  // a timeout, or a third of a shorter one)
  test.setTimeout(30000);
  await page.setContent('<!doctype html><title>Idle</title><p>Idle</p>');
  const capture = await stallWatch.next(page, 25000);
  expect(capture.reason).toBe('test about to time out');
  // nothing runs, so nothing pauses; the profile is taken instead
  expect(capture.paused).toBeUndefined();
  expect(capture.profile.samples).toBeGreaterThan(0);
  expect(capture.answers.task.answered).toBe(true);
  expect(capture.verdict).toContain('free');
  // and the pause it asked for is dropped: the page still runs script
  expect(await page.evaluate(() => 1 + 1)).toBe(2);
});
