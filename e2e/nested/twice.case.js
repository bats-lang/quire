// Three reds in one run, each a different kind (quire#575): a renderer that crashes, a renderer frozen in an untimed futex wait until the test
// times out, and a plain failure that leaves a signal of its own in the ring. Playwright starts a new worker after each red, and the kernel
// ring is the runner's, shared: a ring left paused by the first red would leave the last one with a file that ends before it.
import { spawn } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { join } from 'node:path';
import { test, expect } from '../fixtures.js';

const sleepFor = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

test('first red: a renderer crashes', async ({ page }) => {
  await page.setContent('<p>crash</p>');
  page.goto('chrome://crash').catch(() => {});
  await sleepFor(2500);
  expect(1, 'the renderer crashed').toBe(2);
});

test('second red: a renderer frozen in a futex wait', async ({ page, stallWatch }) => {
  test.setTimeout(30000);
  const server = createServer(() => { /* never answers */ });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  await page.setContent('<p>hang</p>');
  const session = await stallWatch.session(page);
  await session.send('Runtime.evaluate', { expression: `setTimeout(() => { const request = new XMLHttpRequest(); request.open('GET', 'http://127.0.0.1:${server.address().port}/never', false); request.send(); }, 0)` });
  await sleepFor(500);
  await page.evaluate(() => 1);
});

test('third red: a plain failure, after a signal only this test sends', async ({ page }) => {
  await page.setContent('<p>third</p>');
  const child = spawn('sleep', ['30'], { stdio: 'ignore' });
  await sleepFor(300);
  child.kill('SIGUSR2');
  writeFileSync(join(process.cwd(), 'third-event.json'), JSON.stringify({ pid: child.pid, signal: 12 }));
  await sleepFor(300);
  expect(1, 'a plain assertion after two reds').toBe(2);
});
