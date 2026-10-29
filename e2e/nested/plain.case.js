// a test that fails on an assertion with the browser alive: any red has its record. With QUIRE_NESTED_GO it fails only when the file
// `go` is made in its directory, so the run that holds it can act first (quire#985: the run says when, no time is slept)
import { join } from 'node:path';
import { test, expect } from '../fixtures.js';
import { fileAppears } from '../changed.js';

test('plain failure', async ({ page, stallWatch }) => {
  await page.setContent('<p>plain</p>');
  await stallWatch.session(page);   // the page is armed from here
  if (process.env.QUIRE_NESTED_GO) expect(await fileAppears(join(process.cwd(), 'go'), 600000), 'the run made go').toBe(true);
  expect(1, 'a plain assertion').toBe(2);
});
