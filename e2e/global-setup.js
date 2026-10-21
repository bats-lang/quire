/**
 * Before the suite: every spec takes `test` from fixtures.js, so the
 * stall watch (stall-capture.js, #244) is on every test; and the evidence is shown to work (preflight.js, #575): a part that
 * does not fails the run here, by name, and a part that stops later fails it then.
 */

import { readdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { serialRun } from './flight-recorder.js';
import { preflight, startMonitor, teardown } from './preflight.js';

export default async function globalSetup() {
  const directory = dirname(fileURLToPath(import.meta.url));
  const unwatched = readdirSync(directory)
    .filter((name) => name.endsWith('.spec.js'))
    .filter((name) => !/import\s*\{[^}]*\btest\b[^}]*\}\s*from\s*'\.\/fixtures\.js'/.test(readFileSync(join(directory, name), 'utf8')));
  if (unwatched.length) {
    throw new Error(`these specs do not import test from './fixtures.js', so no stall watch: ${unwatched.join(', ')}`);
  }
  // not in the run of the @serial tests, which assert timings (a recorder perturbs them: #741 measured +6% for a trace)
  let started = null;
  if (!serialRun()) {
    try { started = await preflight(); } catch (error) {
      console.error(`::error title=PREFLIGHT FAILED::${error.message}`);
      throw error;
    }
  }
  const stopMonitoring = startMonitor(started);
  return () => teardown(started, stopMonitoring);
}
