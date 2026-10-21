// a real freeze: the main thread blocked in a synchronous request to a server that never answers, until the test's own timeout
import { createServer } from 'node:http';
import { test } from '../fixtures.js';

test('hang', async ({ page, stallWatch }) => {
  const server = createServer(() => { /* never answers */ });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  await page.setContent('<p>hang</p>');
  const session = await stallWatch.session(page);
  await session.send('Runtime.evaluate', { expression: `setTimeout(() => { const request = new XMLHttpRequest(); request.open('GET', 'http://127.0.0.1:${server.address().port}/never', false); request.send(); }, 0)` });
  await new Promise((resolve) => setTimeout(resolve, 500));
  await page.evaluate(() => 1);
});
