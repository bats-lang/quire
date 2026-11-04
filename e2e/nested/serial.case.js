// A red in a test tagged @serial (the timing tests, alone on one worker): it has the same record as any other
import { test, expect } from '../fixtures.js';

test('a timing test that fails', { tag: '@serial' }, async ({ page, stallWatch }) => {
  await page.setContent('<p>serial</p>');
  await stallWatch.session(page);   // the page is armed from here
  expect(1, 'a budget missed').toBe(2);
});
