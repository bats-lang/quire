// Where a place is, in one wording and one scale (#383): a Contents row and
// an annotation's chapter say where in the book they start, the bar's label
// and the footer say the same "N% of book", and Delete is the quiet button
// of a row whose whole is a way to its place.

import { test, expect } from './fixtures.js';
import { start, readBook, place, showChrome, chapters, control, dialog, selectText, selectionButton, bookPage } from './helpers.js';

const book = { title: 'Where Things Are', author: 'Places Tests', rawChapters: chapters(3, 30) };
const contentsRows = page => dialog(page, 'Contents').getByRole('tabpanel', { name: 'Contents' }).locator('.tocline');
const percentOf = text => { const m = /(<1|\d+)%/.exec(text); return m ? (m[1] === '<1' ? 0 : +m[1]) : null; };

test('Contents says where each chapter starts, on the footer\'s scale', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, book);
  await showChrome(page);
  await control(page, 'Contents').click();
  const rows = contentsRows(page);
  await expect(rows).toHaveCount(3);
  const places = await rows.locator('.tocplace').allInnerTexts();
  expect(places).toHaveLength(3);
  for (const text of places) expect(text).toMatch(/^(0|<1|\d+)%$/);
  const numbers = places.map(percentOf);
  expect(numbers[0]).toBeLessThan(numbers[1]);
  expect(numbers[1]).toBeLessThan(numbers[2]);
  // the place beside a row does not take the row's name or its tap
  await rows.nth(1).locator('.tocplace').click({ force: true });
  await expect(dialog(page, 'Contents')).toBeHidden();
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  // the same number, said as the bar says it and as the footer says it
  await showChrome(page);
  const bar = await page.locator('#scrubber-percent').innerText();
  expect(bar).toMatch(/% of book$/);
  expect(percentOf(bar)).toBe(numbers[1]);
  await page.keyboard.press('t');
  await expect(control(page, 'Next page')).toBeHidden();
  const footer = await page.locator('#footer-book').innerText();
  expect(footer).toMatch(/% of book$/);
  expect(percentOf(footer)).toBe(numbers[1]);
  expect(errors).toEqual([]);
});

test('annotations say where their chapter starts, go to it by the whole row, and Delete is quiet', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, book);
  await selectText(page, 0, 8);
  await selectionButton(page, 'Highlight').click();
  await showChrome(page);
  await control(page, 'Annotations').click();
  const panel = dialog(page, 'Annotations');
  await expect(panel).toBeVisible();
  // the chapter's heading says where it starts
  await expect(panel.locator('[id^=annot-place]')).toHaveText(/^ · (0|<1|\d+)%$/);
  // each style's filter shows its swatch beside its name
  for (const swatch of ['filter-yellow-swatch', 'filter-orange-swatch', 'filter-underlined-swatch']) {
    await expect(panel.locator('#' + swatch)).toBeVisible();
  }
  // Add note keeps its edge; Delete has none and is not the same colour
  const add = panel.getByRole('button', { name: 'Add note' });
  const remove = panel.getByRole('button', { name: 'Delete' });
  expect(await add.evaluate(e => getComputedStyle(e).borderTopWidth)).toBe('1px');
  expect(await remove.evaluate(e => getComputedStyle(e).borderTopWidth)).toBe('0px');
  // the row has a go-to cue at its end
  const cue = await panel.locator('.hgo').first().evaluate(e => getComputedStyle(e, '::after').content);
  expect(cue).toContain('›');
  // a tap on the row goes to the highlight
  await panel.locator('.hgo').first().click();
  await expect(panel).toBeHidden();
  expect(errors).toEqual([]);
});
