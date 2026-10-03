/**
 * Before the suite: every spec takes `test` from fixtures.js, so the
 * stall watch (stall-capture.js, #244) is on every test.
 */

import { readdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export default function globalSetup() {
  const directory = dirname(fileURLToPath(import.meta.url));
  const unwatched = readdirSync(directory)
    .filter((name) => name.endsWith('.spec.js'))
    .filter((name) => !/import\s*\{[^}]*\btest\b[^}]*\}\s*from\s*'\.\/fixtures\.js'/.test(readFileSync(join(directory, name), 'utf8')));
  if (unwatched.length) {
    throw new Error(`these specs do not import test from './fixtures.js', so no stall watch: ${unwatched.join(', ')}`);
  }
}
