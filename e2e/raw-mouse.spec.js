// The page's mouse is refused to a spec (fixtures.js refuseRawMouse, #649):
// a raw call throws however it is written, and rawMouse still reaches the
// real mouse (helpers.js).
import { test, expect } from './fixtures.js';
import { rawMouse } from './helpers.js';

test('a spec cannot call the page mouse directly, by name, by a computed key or through an alias', async ({ page }) => {
  const refused = /use rawMouse \(e2e\/helpers\.js\)/;
  expect(() => page.mouse.click(1, 2)).toThrow(refused);
  expect(() => page['mou' + 'se'].down()).toThrow(refused);
  const alias = page;
  expect(() => alias.mouse.move(1, 2)).toThrow(refused);
});

test('rawMouse still makes a raw pointer event', async ({ page }) => {
  await page.setContent('<button id="b" onclick="this.dataset.clicked = 1">b</button>');
  await rawMouse(page, 'move', 0, 0);
  await rawMouse(page, 'down');
  await rawMouse(page, 'up');
  await rawMouse(page, 'click', 5, 5);
  await expect(page.locator('#b')).toBeAttached();
});
