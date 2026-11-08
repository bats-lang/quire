// A press whose release is lost (quire#1079): the press is sent over a DevTools session of the case's own, mousePressed with no mouseReleased
// after it, so the page gets a pointerdown and a mousedown and never a pointerup, a mouseup or a click, and the expect for the click fails.
// The press record of the failed test (e2e/press-record.js) must hold the page's events, the browser's input path and the DevTools clients.
import { test, expect } from '../fixtures.js';

test('lost release', async ({ page }) => {
  // navigated to, not set: document.open (what setContent does) removes the listeners the press record's init script put on window
  const html = '<button id="b" style="position:fixed;left:20px;top:20px;width:120px;height:40px">press</button><p id="state">waiting</p>'
    + '<script>document.getElementById("b").onclick = () => { document.getElementById("state").textContent = "clicked"; };</script>';
  await page.goto(`data:text/html,${encodeURIComponent(html)}`);
  const box = await page.locator('#b').boundingBox();
  const x = box.x + box.width / 2;
  const y = box.y + box.height / 2;
  // the case's own DevTools client, whose commands the record lists with the case's file as the one that made it
  const session = await page.context().newCDPSession(page);
  await session.send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
  await session.send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
  // the release is never sent: the click does not come
  await expect(page.locator('#state')).toHaveText('clicked', { timeout: 1500 });
});
