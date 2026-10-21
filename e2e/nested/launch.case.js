// a browser that cannot start (the executable is QUIRE_NESTED_EXECUTABLE): the failure is before the stall watch exists
import { test } from '../fixtures.js';

test('launch', async ({ page }) => {
  await page.setContent('<p>never</p>');
});
