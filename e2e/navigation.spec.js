// Finding one's way in a book: its table of contents (EPUB 3 nav or
// EPUB 2 NCX), the scrubber, and the back button that follows jumps.

import { test, expect } from '@playwright/test';
import { start, readBook, place, visibleText, showChrome } from './helpers.js';

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
    await expect(page.locator('#qcht')).toHaveText('Opening & Intro');
    await showChrome(page);
    await page.locator('#qtcb').click();
    await expect(page.locator('#qtoc')).toBeVisible();
    await expect(page.locator('#qtct')).toHaveAttribute('aria-selected', 'true');
    const rows = await page.locator('#qtcl [id^=qe]').allInnerTexts();
    expect(rows.map(r => r.trim())).toEqual(['Opening & Intro', 'The Middle', 'Deep in two', 'The End']);
    // the entry to a place inside a chapter shows that place
    await page.locator('#qtcl [id^=qe]', { hasText: 'Deep in two' }).click();
    await expect(page.locator('#qtoc')).toBeHidden();
    await expect(page.locator('#qcht')).toHaveText('The Middle');
    await expect.poll(() => visibleText(page)).toContain('Deep target 2');
    expect((await place(page)).p).toBeGreaterThan(1);
    // back to where the jump was made
    await expect(page.locator('#qpbk')).toBeVisible();
    await page.locator('#qpbk').click();
    await expect(page.locator('#qcht')).toHaveText('Opening & Intro');
    expect(await place(page)).toMatchObject({ ch: 1, p: 1 });
    await expect(page.locator('#qpbk')).toBeHidden();
    expect(errors).toEqual([]);
  });
}

test('the contents panel closes with Escape and its close button', async ({ page }) => {
  await start(page);
  await readBook(page, tocBook(false));
  await showChrome(page);
  await page.locator('#qtcb').click();
  await expect(page.locator('#qtoc')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.locator('#qtoc')).toBeHidden();
  await expect(page.locator('#qrvw')).toBeVisible();
  await showChrome(page);
  await page.locator('#qtcb').click();
  await page.locator('#qtcx').click();
  await expect(page.locator('#qtoc')).toBeHidden();
});

test('the scrubber shows where the page is, and dragging it goes there', async ({ page }) => {
  await start(page);
  await readBook(page, tocBook(false));
  await showChrome(page);
  await expect(page.locator('#qpct')).toHaveText('0%');
  // a tick where each chapter starts after the first
  await expect(page.locator('#qstk .tick')).toHaveCount(2);
  const box = await page.locator('#qtrk').boundingBox();
  await page.mouse.move(box.x + box.width * 0.8, box.y + box.height / 2);
  await page.mouse.down();
  await expect(page.locator('#qstt')).toBeVisible();
  await expect(page.locator('#qstt')).toContainText('The End');
  await page.mouse.up();
  await expect(page.locator('#qcht')).toHaveText('The End');
  await showChrome(page);
  const pct = parseInt(await page.locator('#qpct').innerText(), 10);
  expect(pct).toBeGreaterThanOrEqual(70);
  expect(pct).toBeLessThanOrEqual(85);
  // the jump can be gone back from
  await expect(page.locator('#qpbk')).toBeVisible();
  await page.locator('#qpbk').click();
  await expect(page.locator('#qcht')).toHaveText('Opening & Intro');
});
