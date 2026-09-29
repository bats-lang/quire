// Finding one's way in a book: its table of contents (EPUB 3 nav or
// EPUB 2 NCX), the scrubber, and the back button that follows jumps.

import { test, expect } from '@playwright/test';
import {
  start, readBook, place, visibleText, showChrome, chapterTitle, control, dialog, jumpBack, bookPage,
} from './helpers.js';

const contents = page => dialog(page, 'Contents');
const entries = page => contents(page).getByRole('tabpanel', { name: 'Contents' }).getByRole('button');

function tocBook(ncx) {
  const rawChapters = [1, 2, 3].map(i => ({
    body: `<h1>Part ${i}</h1>` +
      Array.from({ length: 30 }, (_, k) => `<p>Para ${i}.${k} ` + 'lorem ipsum dolor sit amet '.repeat(12) + '</p>').join('') +
      `<p id="deep${i}">Deep target ${i}</p>`,
  }));
  const toc = [
    { label: 'Opening &amp; Intro', href: 'chapter1.xhtml' },
    { label: 'The Middle', href: 'chapter2.xhtml', children: [{ label: 'Deep in two', href: 'chapter2.xhtml#deep2' }] },
    { label: 'The End', href: 'chapter3.xhtml' },
  ];
  return { title: ncx ? 'NCX Book' : 'Nav Book', author: 'Toc Tests', rawChapters, toc, ncx };
}

for (const ncx of [false, true]) {
  test(`the ${ncx ? 'NCX' : 'nav'} table of contents names the chapters and goes to them`, async ({ page }) => {
    const errors = await start(page);
    await readBook(page, tocBook(ncx));
    await expect(chapterTitle(page)).toHaveText('Opening & Intro');
    await showChrome(page);
    await control(page, 'Contents').click();
    await expect(contents(page)).toBeVisible();
    await expect(contents(page).getByRole('tab', { name: 'Contents' })).toHaveAttribute('aria-selected', 'true');
    const rows = await entries(page).allInnerTexts();
    expect(rows.map(r => r.trim())).toEqual(['Opening & Intro', 'The Middle', 'Deep in two', 'The End']);
    // the entry to a place inside a chapter shows that place
    await entries(page).filter({ hasText: 'Deep in two' }).click();
    await expect(contents(page)).toBeHidden();
    await expect(chapterTitle(page)).toHaveText('The Middle');
    await expect.poll(() => visibleText(page)).toContain('Deep target 2');
    expect((await place(page)).p).toBeGreaterThan(1);
    // back to where the jump was made
    await expect(jumpBack(page)).toBeVisible();
    await jumpBack(page).click();
    await expect(chapterTitle(page)).toHaveText('Opening & Intro');
    expect(await place(page)).toMatchObject({ ch: 1, p: 1 });
    await expect(jumpBack(page)).toBeHidden();
    expect(errors).toEqual([]);
  });
}

test('reading on from where a jump landed puts the back button away', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, tocBook(false));
  await showChrome(page);
  await control(page, 'Contents').click();
  await entries(page).filter({ hasText: 'The End' }).click();
  await expect(chapterTitle(page)).toHaveText('The End');
  await expect(jumpBack(page)).toBeVisible();
  // turning the page on keeps the new place: nothing to go back to
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(2);
  await expect(jumpBack(page)).toBeHidden();
  // and so does turning back, after another jump
  await showChrome(page);
  await control(page, 'Contents').click();
  await entries(page).filter({ hasText: 'The Middle' }).click();
  await expect(chapterTitle(page)).toHaveText('The Middle');
  await expect(jumpBack(page)).toBeVisible();
  await page.keyboard.press('ArrowLeft');
  await expect.poll(async () => (await place(page)).ch).toBe(1);
  await expect(jumpBack(page)).toBeHidden();
  expect(errors).toEqual([]);
});

test('the back button goes on its own after ten seconds, and with it the place it offered', async ({ page }) => {
  await page.clock.install();
  const errors = await start(page);
  await readBook(page, tocBook(false));
  await showChrome(page);
  await control(page, 'Contents').click();
  await entries(page).filter({ hasText: 'The End' }).click();
  await expect(chapterTitle(page)).toHaveText('The End');
  await expect(jumpBack(page)).toBeVisible();
  await page.clock.runFor(9000);
  await expect(jumpBack(page)).toBeVisible();
  await page.clock.runFor(1500);
  await expect(jumpBack(page)).toBeHidden();
  // a later jump offers only its own way back
  await showChrome(page);
  await control(page, 'Contents').click();
  await entries(page).filter({ hasText: 'The Middle' }).click();
  await expect(chapterTitle(page)).toHaveText('The Middle');
  await jumpBack(page).click();
  await expect(chapterTitle(page)).toHaveText('The End');
  await expect(jumpBack(page)).toBeHidden();
  expect(errors).toEqual([]);
});

test('bringing up the bars puts the back button away', async ({ page }) => {
  await page.clock.install();
  const errors = await start(page);
  await readBook(page, tocBook(false));
  await showChrome(page);
  await control(page, 'Contents').click();
  await entries(page).filter({ hasText: 'The End' }).click();
  await expect(chapterTitle(page)).toHaveText('The End');
  // the bars go by themselves after five seconds; the button stays
  await page.clock.runFor(6000);
  await expect(control(page, 'Previous page')).toBeHidden();
  await expect(jumpBack(page)).toBeVisible();
  await showChrome(page);
  await expect(jumpBack(page)).toBeHidden();
  expect(errors).toEqual([]);
});

test('the contents panel closes with Escape and its close button', async ({ page }) => {
  await start(page);
  await readBook(page, tocBook(false));
  await showChrome(page);
  await control(page, 'Contents').click();
  await expect(contents(page)).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(contents(page)).toBeHidden();
  await expect(bookPage(page)).toBeVisible();
  await showChrome(page);
  await control(page, 'Contents').click();
  await contents(page).getByRole('button', { name: 'Close' }).click();
  await expect(contents(page)).toBeHidden();
});

test('the scrubber shows where the page is, and dragging it goes there', async ({ page }) => {
  await start(page);
  await readBook(page, tocBook(false));
  await showChrome(page);
  const scrubber = page.getByRole('slider', { name: 'Place in book' });
  await expect(scrubber).toHaveAttribute('aria-valuenow', '0');
  await expect(page.getByText('0%', { exact: true })).toBeVisible();
  const box = await scrubber.boundingBox();
  await page.mouse.move(box.x + box.width * 0.8, box.y + box.height / 2);
  await page.mouse.down();
  await expect(page.getByRole('tooltip')).toBeVisible();
  await expect(page.getByRole('tooltip')).toContainText('The End');
  await page.mouse.up();
  await expect(chapterTitle(page)).toHaveText('The End');
  await showChrome(page);
  const pct = +(await scrubber.getAttribute('aria-valuenow'));
  expect(pct).toBeGreaterThanOrEqual(70);
  expect(pct).toBeLessThanOrEqual(85);
  // the jump can be gone back from
  await expect(jumpBack(page)).toBeVisible();
  await jumpBack(page).click();
  await expect(chapterTitle(page)).toHaveText('Opening & Intro');
});
