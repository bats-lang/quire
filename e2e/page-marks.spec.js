// What the page itself shows once the bars hide: a bookmarked page's mark
// in its top-right corner (Kindle and Kobo draw theirs there), and the
// bar's chapter steps, which make the next chapter two taps from the page
// (the bars up, then the button) where the contents took three (#388).

import { test, expect } from './fixtures.js';
import { start, readBook, place, showChrome, chapters, control, bookPage } from './helpers.js';

const star = page => page.getByRole('button', { name: 'Bookmark this page' });
const mark = page => page.locator('#bookmark-mark');
const book = { title: 'Page Marks', author: 'Marks Tests', rawChapters: chapters(3) };

async function hideBars(page) {
  await page.keyboard.press('t');
  await expect(control(page, 'Next page')).toBeHidden();
}

test('a bookmarked page shows its mark in the top-right band after the bars hide', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, book);
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(2);
  // no mark on a page that is not bookmarked
  await hideBars(page);
  await expect(mark(page)).toBeHidden();
  await showChrome(page);
  await star(page).click();
  await expect(star(page)).toHaveAttribute('aria-pressed', 'true');
  // with the bars up the star says it; the mark waits for them to hide
  await expect(mark(page)).toBeHidden();
  await hideBars(page);
  await expect(mark(page)).toBeVisible();
  // in the corner, inside the band the text keeps clear of
  const band = await bookPage(page).evaluate(el => parseFloat(getComputedStyle(el).paddingTop));
  const box = await mark(page).boundingBox();
  const width = page.viewportSize().width;
  expect(box.y).toBeGreaterThanOrEqual(0);
  expect(box.y + box.height).toBeLessThanOrEqual(band + 0.5);
  expect(box.x + box.width).toBeLessThanOrEqual(width);
  expect(box.x).toBeGreaterThan(width / 2);
  // on that page only
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(3);
  await expect(mark(page)).toBeHidden();
  await page.keyboard.press('ArrowLeft');
  await expect.poll(async () => (await place(page)).p).toBe(2);
  await expect(mark(page)).toBeVisible();
  // taking the bookmark away takes the mark
  await showChrome(page);
  await star(page).click();
  await expect(star(page)).toHaveAttribute('aria-pressed', 'false');
  await hideBars(page);
  await expect(mark(page)).toBeHidden();
  expect(errors).toEqual([]);
});

test('the bar steps a chapter at a time, in two taps from the page', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, book);
  // from the page: the bars up, then the button
  await showChrome(page);
  await expect(control(page, 'Previous chapter')).toBeHidden();
  await control(page, 'Next chapter').click();
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  expect((await place(page)).p).toBe(1);
  await control(page, 'Next chapter').click();
  await expect.poll(async () => (await place(page)).ch).toBe(3);
  // the last chapter has none after it
  await expect(control(page, 'Next chapter')).toBeHidden();
  await control(page, 'Previous chapter').click();
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  await control(page, 'Previous chapter').click();
  await expect.poll(async () => (await place(page)).ch).toBe(1);
  await expect(control(page, 'Previous chapter')).toBeHidden();
  expect(errors).toEqual([]);
});
