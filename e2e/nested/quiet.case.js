// a test that does nothing for a while (QUIRE_NESTED_SLEEP ms): the run in which the evidence's parts are made to fail
import { test } from '../fixtures.js';

test('quiet', async ({ page }) => {
  await page.setContent('<p>quiet</p>');
  await new Promise((resolve) => setTimeout(resolve, Number(process.env.QUIRE_NESTED_SLEEP || 1000)));
});
