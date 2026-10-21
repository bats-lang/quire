// a test that fails on an assertion with the browser alive: any red has its record
import { test, expect } from '../fixtures.js';

test('plain failure', async ({ page }) => {
  await page.setContent('<p>plain</p>');
  await new Promise((resolve) => setTimeout(resolve, Number(process.env.QUIRE_NESTED_SLEEP || 500)));
  expect(1, 'a plain assertion').toBe(2);
});
