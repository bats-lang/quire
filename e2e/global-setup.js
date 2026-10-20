/**
 * Before the suite: every spec takes `test` from fixtures.js, so the
 * stall watch (stall-capture.js, #244) is on every test.
 */

import { readdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { startKernel, stopKernel } from './flight-recorder.js';

export default async function globalSetup(config) {
  const directory = dirname(fileURLToPath(import.meta.url));
  const unwatched = readdirSync(directory)
    .filter((name) => name.endsWith('.spec.js'))
    .filter((name) => !/import\s*\{[^}]*\btest\b[^}]*\}\s*from\s*'\.\/fixtures\.js'/.test(readFileSync(join(directory, name), 'utf8')));
  if (unwatched.length) {
    throw new Error(`these specs do not import test from './fixtures.js', so no stall watch: ${unwatched.join(', ')}`);
  }
  // the kernel's ring of the run (flight recorder, #575), started before any worker; the teardown removes it
  // not in the run of the @serial tests, which assert timings (a recorder perturbs them: #741 measured +6% for a trace)
  const measuring = [config && config.grep].flat().some((pattern) => pattern && String(pattern.source || pattern).includes('@serial'));
  const kernel = measuring ? null : await startKernel();
  if (kernel) console.error(`[flight-recorder] kernel ring: ${kernel.instance ? `${kernel.instance}${kernel.skipped && kernel.skipped.length ? `, skipped ${kernel.skipped.join('; ')}` : ''}` : `not started: ${kernel.error}`}`);
  return () => stopKernel(kernel);
}
