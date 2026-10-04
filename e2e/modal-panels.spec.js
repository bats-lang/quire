// The reader's panels are modal (Material 3's modal bottom sheet, the
// WAI-ARIA modal dialog): while one is open the page behind it does not
// turn (no tap, drag or key reaches it), a tap on the scrim outside it
// closes it, the focus stays inside it and goes back to the button that
// opened it, and Escape closes it.

import { test, expect } from './fixtures.js';
import { start, readBook, chapters, bookPage, dialog, place, clickControl, control, showChrome } from './helpers.js';

// Each panel the bars open: its button (the bottom bar's, or the top
// bar's Search) and its dialog's name
const panels = [
  { button: 'Typography', name: 'Typography and theme' },
  { button: 'Contents', name: 'Contents' },
  { button: 'Annotations', name: 'Annotations' },
  { button: 'Search in book', name: 'Search in book', top: true },
];

const opener = (page, panel) => panel.top
  ? page.getByRole('navigation', { name: 'Book' }).getByRole('button', { name: panel.button, exact: true })
  : control(page, panel.button);

async function open(page, panel) {
  if (panel.top) {
    await expect(async () => {
      await showChrome(page);
      await opener(page, panel).click({ timeout: 2000 });
    }).toPass({ timeout: 20000 });
  } else {
    await clickControl(page, panel.button);
  }
  const sheet = dialog(page, panel.name);
  await expect(sheet).toBeVisible();
  await expect(sheet).toHaveAttribute('aria-modal', 'true');
  // the focus is inside the panel
  await expect(sheet.locator(':focus')).toHaveCount(1);
  return sheet;
}

// A point of the page's box outside the panel's, in a side's tap zone,
// where a tap would turn the page; null when the panel covers both
async function outside(page, sheet) {
  const pageBox = await bookPage(page).boundingBox();
  const box = await sheet.boundingBox();
  for (const y of [pageBox.y + pageBox.height / 3, pageBox.y + 24]) {
    for (const x of [pageBox.x + 12, pageBox.x + pageBox.width - 12]) {
      const inside = x >= box.x && x <= box.x + box.width && y >= box.y && y <= box.y + box.height;
      if (!inside) return { x, y };
    }
  }
  return null;
}

// A drag of touch pointer events on the page itself, as the gestures
// recognizer gets them (dispatched to the page, so past the scrim: what
// stops it is the reader's own check)
const touchDrag = (page, x0, x1, y) =>
  bookPage(page).evaluate(async (el, [x0, x1, y]) => {
    const ev = (type, x) => el.dispatchEvent(new PointerEvent(type, {
      bubbles: true, pointerId: 41, pointerType: 'touch', isPrimary: true, clientX: x, clientY: y,
    }));
    const wait = (t) => new Promise((r) => setTimeout(r, t));
    ev('pointerdown', x0);
    for (let i = 1; i <= 4; i++) { await wait(16); ev('pointermove', x0 + ((x1 - x0) * i) / 4); }
    await wait(16);
    ev('pointerup', x1);
  }, [x0, x1, y]);

async function reading(page, title) {
  const errors = await start(page);
  await readBook(page, { title, author: 'Modal Tests', rawChapters: chapters(2, 40) });
  // one page on, so a turn either way would show
  await clickControl(page, 'Next page');
  await expect.poll(async () => (await place(page)).p).toBe(2);
  return errors;
}

for (const panel of panels) {
  test(`${panel.button}: the page does not turn behind the panel, the scrim closes it and the focus goes back`, async ({ page }) => {
    const errors = await reading(page, `Modal ${panel.button}`);
    const before = await place(page);
    let sheet = await open(page, panel);

    // keys: none turns the page, and the panel stays
    for (const key of ['ArrowRight', 'ArrowLeft', 'PageDown', 'PageUp']) await page.keyboard.press(key);
    await expect(sheet).toBeVisible();
    // a touch drag on the page reaches no recognizer
    const pageBox = await bookPage(page).boundingBox();
    const mid = pageBox.x + pageBox.width / 2;
    await touchDrag(page, mid + 80, mid - 80, pageBox.y + pageBox.height / 2);
    await touchDrag(page, mid - 80, mid + 80, pageBox.y + pageBox.height / 2);
    await page.waitForTimeout(500);
    expect(await place(page)).toEqual(before);
    await expect(sheet).toBeVisible();

    // a drag across the page area outside the panel lands on the scrim:
    // the page stays where it was
    const point = await outside(page, sheet);
    expect(point, 'the scrim shows beside or above the panel').not.toBeNull();
    await page.mouse.move(point.x, point.y);
    await page.mouse.down();
    await page.mouse.move(point.x + 40, point.y, { steps: 4 });
    await page.mouse.up();
    await page.waitForTimeout(500);
    expect(await place(page)).toEqual(before);

    // a tap on the scrim, in a side's tap zone: the panel closes, the
    // page stays, and the focus is back on the button that opened it
    if (!(await sheet.isVisible())) sheet = await open(page, panel);
    await page.mouse.click(point.x, point.y);
    await expect(sheet).toBeHidden();
    await expect(page.locator('#panel-scrim')).toBeHidden();
    await expect(opener(page, panel)).toBeFocused();
    await page.waitForTimeout(500);
    expect(await place(page)).toEqual(before);

    // Escape closes it too, the focus back on its button
    sheet = await open(page, panel);
    await page.keyboard.press('Escape');
    await expect(sheet).toBeHidden();
    await expect(opener(page, panel)).toBeFocused();
    expect(await place(page)).toEqual(before);

    // the page turns again once the panel is gone
    await page.keyboard.press('ArrowRight');
    await expect.poll(async () => (await place(page)).p).toBe(before.p + 1);
    expect(errors).toEqual([]);
  });
}

test('Tab keeps to an open panel, round from its last element to its first and back', async ({ page }) => {
  const errors = await reading(page, 'Modal Tab');
  const sheet = await open(page, panels[0]);
  const focusedId = () => page.evaluate(() => document.activeElement && document.activeElement.id);
  const inside = () => sheet.evaluate(el => el.contains(document.activeElement));
  // forward, past the panel's last element (Close): round to its first
  await sheet.getByRole('button', { name: 'Close', exact: true }).focus();
  await page.keyboard.press('Tab');
  expect(await inside()).toBe(true);
  const first = await focusedId();
  expect(first).not.toBe('typography-close');
  // back from the first: round to the last
  await page.keyboard.press('Shift+Tab');
  expect(await focusedId()).toBe('typography-close');
  // all the way round, never leaving the panel
  for (let i = 0; i < 40; i++) {
    await page.keyboard.press('Tab');
    expect(await inside()).toBe(true);
  }
  await page.keyboard.press('Escape');
  await expect(sheet).toBeHidden();
  expect(errors).toEqual([]);
});
