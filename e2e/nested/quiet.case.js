// a test that does nothing, and with QUIRE_NESTED_GO until the run that holds it ends it or makes the file `go` in its directory: the run in which the
// evidence's parts are made to fail (quire#985: the run says when, no time is slept)
import { join } from 'node:path';
import { test, expect } from '../fixtures.js';
import { fileAppears } from '../changed.js';

test('quiet', async ({ page }) => {
  await page.setContent('<p>quiet</p>');
  if (process.env.QUIRE_NESTED_GO) expect(await fileAppears(join(process.cwd(), 'go'), 600000), 'the run made go').toBe(true);
});
