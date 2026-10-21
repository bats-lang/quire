// a real freeze with the stall watch off (the run sets QUIRE_NO_STALL_WATCH): the page is frozen through a DevTools session of this case's own,
// not the stall watch's, which does nothing, and the test runs into its timeout
import { createServer } from 'node:http';
import { test } from '../fixtures.js';

test('hang with the stall watch off', async ({ page }) => {
  const server = createServer(() => { /* never answers */ });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  await page.setContent('<p>hang</p>');
  const session = await page.context().newCDPSession(page);
  await session.send('Runtime.evaluate', { expression: `setTimeout(() => { const request = new XMLHttpRequest(); request.open('GET', 'http://127.0.0.1:${server.address().port}/never', false); request.send(); }, 0)` });
  await new Promise((resolve) => setTimeout(resolve, 500));
  await page.evaluate(() => 1);
});
