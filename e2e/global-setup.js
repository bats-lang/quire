/**
 * Before the suite: every spec takes `test` from fixtures.js, so the
 * stall watch (stall-capture.js, #244) is on every test; and the evidence is shown to work (preflight.js, #575): a part that
 * does not fails the run here, by name, and a part that stops later fails it then.
 */

import { readdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { preflight, startMonitor, teardown } from './preflight.js';

export default async function globalSetup(config) {
  const directory = dirname(fileURLToPath(import.meta.url));
  const unwatched = readdirSync(directory)
    .filter((name) => name.endsWith('.spec.js'))
    .filter((name) => !/import\s*\{[^}]*\btest\b[^}]*\}\s*from\s*'\.\/fixtures\.js'/.test(readFileSync(join(directory, name), 'utf8')));
  if (unwatched.length) {
    throw new Error(`these specs do not import test from './fixtures.js', so no stall watch: ${unwatched.join(', ')}`);
  }
  // in every run, the @serial one too (alone on one worker, it is where pathological.spec.js stalls): a red there has the same record as any other
  let started = null;
  try { started = await preflight(process.env, { launchOptions: (config && config.projects && config.projects[0] && config.projects[0].use && config.projects[0].use.launchOptions) || null }); } catch (error) {
    console.error(`::error title=PREFLIGHT FAILED::${error.message}`);
    throw error;
  }
  const stopMonitoring = startMonitor(started);
  return () => teardown(started, stopMonitoring);
}
