// DevTools session loss with the browser alive: the page's target is closed from under the test, which then fails with "Target closed"
import { test } from '../fixtures.js';

test('devtools session lost', async ({ page, browser }) => {
  await page.setContent('<p>devtools</p>');
  const session = await browser.newBrowserCDPSession();
  const { targetInfos } = await session.send('Target.getTargets');
  const mine = targetInfos.find((target) => target.type === 'page');
  await session.send('Target.closeTarget', { targetId: mine.targetId });
  await page.evaluate(() => 1);
});
