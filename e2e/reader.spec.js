// Reading: turning pages every way the reader offers, chapters, the
// bars, keeping the place, and what a chapter's XHTML becomes on the
// page.

import { test, expect } from '@playwright/test';
import { TINY_PNG } from './create-epub.js';
import {
  start, openBook, readBook, place, placeChanged, startsOnPage, onPage, visibleText, toLibrary,
  showChrome, chapters, card, bookPage, chapterTitle, control, jumpBack, librarySearch, openSettings,
} from './helpers.js';

const book = (title, n = 3, paras = 20) => ({ title, author: 'Reader Tests', rawChapters: chapters(n, paras) });

test('a book opens on its first page with its first chapter shown', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, book('First Page'));
  expect(await place(page)).toMatchObject({ ch: 1, p: 1 });
  expect(await visibleText(page)).toContain('Para 1.0');
  await expect(chapterTitle(page)).toHaveText('Chapter 1');
  expect(errors).toEqual([]);
});

test('the page buttons turn pages, and across chapters', async ({ page }) => {
  await start(page);
  await readBook(page, book('Buttons', 2));
  const first = await place(page);
  expect(first.t).toBeGreaterThan(1);
  await showChrome(page);
  await control(page, 'Next page').click();
  expect(await placeChanged(page, first)).toMatchObject({ ch: 1, p: 2 });
  await showChrome(page);
  await control(page, 'Previous page').click();
  expect(await placeChanged(page, { ...first, p: 2 })).toMatchObject({ ch: 1, p: 1 });
  // the last page of chapter 1, then on into chapter 2
  await page.keyboard.press('End');
  await expect.poll(async () => (await place(page)).p).toBe(first.t);
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  expect((await place(page)).p).toBe(1);
  expect(await visibleText(page)).toContain('Part 2');
  // and back to the last page of chapter 1
  await page.keyboard.press('ArrowLeft');
  await expect.poll(async () => JSON.stringify(await place(page))).toBe(JSON.stringify({ ch: 1, p: first.t, t: first.t }));
});

test('the keys turn pages', async ({ page }) => {
  await start(page);
  await readBook(page, book('Keys'));
  const t = (await place(page)).t;
  const at = async p => expect.poll(async () => (await place(page)).p).toBe(p);
  await page.keyboard.press('ArrowRight'); await at(2);
  await page.keyboard.press('PageDown'); await at(3);
  await page.keyboard.press('Space'); await at(4);
  await page.keyboard.press('Shift+Space'); await at(3);
  await page.keyboard.press('PageUp'); await at(2);
  await page.keyboard.press('ArrowLeft'); await at(1);
  await page.keyboard.press('End'); await at(t);
  await page.keyboard.press('Home'); await at(1);
});

test('tapping the page\'s sides turns it, and its middle shows or hides the bars', async ({ page }) => {
  await start(page);
  await readBook(page, book('Taps'));
  const box = await bookPage(page).boundingBox();
  const y = box.y + box.height / 2;
  await page.mouse.click(box.x + box.width - 10, y);
  await expect.poll(async () => (await place(page)).p).toBe(2);
  // a page turn hides the bars
  await expect(control(page, 'Previous page')).toBeHidden();
  await page.mouse.click(box.x + 10, y);
  await expect.poll(async () => (await place(page)).p).toBe(1);
  await page.mouse.click(box.x + box.width / 2, y);
  await expect(control(page, 'Previous page')).toBeVisible();
  await page.mouse.click(box.x + box.width / 2, y);
  await expect(control(page, 'Previous page')).toBeHidden();
});

test('the bars hide by themselves after a few seconds', async ({ page }) => {
  await start(page);
  await readBook(page, book('Auto Hide'));
  await showChrome(page);
  await expect(control(page, 'Previous page')).toBeHidden({ timeout: 8000 });
});

test('the mouse wheel turns pages', async ({ page }) => {
  await start(page);
  await readBook(page, book('Wheel'));
  const box = await bookPage(page).boundingBox();
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.wheel(0, 120);
  await expect.poll(async () => (await place(page)).p).toBe(2);
  await page.waitForTimeout(400);
  await page.mouse.wheel(0, -120);
  await expect.poll(async () => (await place(page)).p).toBe(1);
});

test('the back arrow, Escape and the browser\'s back all return to the library', async ({ page }) => {
  await start(page);
  await readBook(page, book('Ways Back'));
  await showChrome(page);
  await page.getByRole('button', { name: 'Back to library' }).click();
  await expect(librarySearch(page)).toBeVisible();
  await openBook(page, 'Ways Back');
  await page.keyboard.press('Escape'); // the bars
  await page.keyboard.press('Escape'); // the library
  await expect(librarySearch(page)).toBeVisible();
  await openBook(page, 'Ways Back');
  await page.goBack();
  await expect(librarySearch(page)).toBeVisible();
});

test('the place is kept when the book is opened again, and after a reload', async ({ page }) => {
  await start(page);
  await readBook(page, book('Keep Place', 3, 30));
  await page.keyboard.press('ArrowRight');
  await page.keyboard.press('ArrowRight');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(4);
  const at = await place(page);
  const top = (await startsOnPage(page))[0];
  await toLibrary(page);
  await openBook(page, 'Keep Place');
  expect(await place(page)).toEqual(at);
  expect((await startsOnPage(page))[0]).toBe(top);
  await toLibrary(page);
  await page.reload();
  await openBook(page, 'Keep Place');
  expect(await place(page)).toEqual(at);
  expect((await startsOnPage(page))[0]).toBe(top);
});

test('the place is kept in a later chapter too', async ({ page }) => {
  await start(page);
  await readBook(page, book('Later Chapter', 3));
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => JSON.stringify(await place(page))).toMatch(/"ch":2,"p":2/);
  const at = await place(page);
  await toLibrary(page);
  await page.reload();
  await openBook(page, 'Later Chapter');
  expect(await place(page)).toEqual(at);
});

test('a new type size or window size keeps the page\'s text in view', async ({ page }) => {
  await start(page);
  await readBook(page, book('Relayout', 2, 30));
  for (let k = 0; k < 3; k++) await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(4);
  const top = (await startsOnPage(page))[0];
  await openSettings(page);
  await page.getByRole('slider', { name: 'Size' }).fill('26');
  await page.keyboard.press('Escape');
  await expect.poll(() => onPage(page, top)).toBe(true);
  const size = page.viewportSize();
  await page.setViewportSize({ width: Math.round(size.width * 0.7), height: size.height });
  await expect.poll(() => onPage(page, top)).toBe(true);
});

test('a chapter over 1 MiB is shown whole', async ({ page }) => {
  const errors = await start(page);
  const para = k => ('Paragraph ' + k + ' ' + 'lorem ipsum dolor sit amet '.repeat(1300)).slice(0, 32768);
  let body = '<h1>Chapter 1</h1>\n';
  for (let k = 0; k < 39; k++) body += `<p>${para(k)}</p>\n`;
  body += '<p>THE-LAST-PARAGRAPH</p>\n';
  expect(body.length).toBeGreaterThan(1048576);
  await readBook(page, { title: 'Long Chapter', author: 'Bot', rawChapters: [{ body }, { body: '<p>short</p>' }] });
  await expect.poll(() => bookPage(page).evaluate(el => /THE-LAST-PARAGRAPH/.test(el.textContent) && el.textContent.length > 1048576)).toBe(true);
  await page.keyboard.press('End');
  expect(await visibleText(page)).toContain('THE-LAST-PARAGRAPH');
  expect(errors).toEqual([]);
});

test('a text of over 64 KiB is shown whole, no character cut', async ({ page }) => {
  await start(page);
  const text = 'START-' + ('é' + 'abcdefg').repeat(19200) + '-END';
  await readBook(page, { title: 'Long Text', author: 'Bot', rawChapters: [{ body: `<p>${text}</p>` }] });
  await expect.poll(() => bookPage(page).evaluate((el, t) => el.textContent.includes(t), text)).toBe(true);
  expect(await bookPage(page).evaluate(el => el.textContent.includes('�'))).toBe(false);
});

test('an EPUB over 1 MiB is imported, read and kept', async ({ page }) => {
  const errors = await start(page);
  const big = Buffer.alloc(1536 * 1024);
  for (let i = 0; i < big.length; i++) big[i] = (i * 7919) & 0xff;
  await readBook(page, { ...book('Big Book', 2, 8), extraEntries: [{ name: 'OEBPS/images/big.bin', data: big, store: true }] });
  expect(await visibleText(page)).toContain('Para 1.0');
  await toLibrary(page);
  await page.reload();
  await openBook(page, 'Big Book');
  expect(await visibleText(page)).toContain('Para 1.0');
  expect(errors).toEqual([]);
});

test('a chapter\'s images are shown, and a missing one is left empty', async ({ page }) => {
  await start(page);
  const body = `<h1>Pictures</h1>
<p><img src="images/a.png" alt="stored"/></p>
<p><img src="../OEBPS/images/b.png" alt="dotdot"/></p>
<p><img src="images/c.png#frag" alt="deflated"/></p>
<p><img src="images/missing.png" alt="missing"/></p>
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 1 1"><image width="1" height="1" xlink:href="images/a.png"/></svg>`;
  await readBook(page, {
    title: 'Pictures', author: 'Bot', rawChapters: [{ body }],
    extraEntries: [
      { name: 'OEBPS/images/a.png', data: TINY_PNG, store: true },
      { name: 'OEBPS/images/b.png', data: TINY_PNG, store: true },
      { name: 'OEBPS/images/c.png', data: TINY_PNG },
    ],
  });
  await expect.poll(() => bookPage(page).evaluate(doc => {
    const imgs = [...doc.querySelectorAll('img')];
    return imgs.filter(i => i.alt !== 'missing' && i.src.startsWith('blob:') && i.complete && i.naturalWidth === 1).length;
  })).toBe(4);
  expect(await bookPage(page).getByRole('img', { name: 'missing' }).getAttribute('src')).toBe('data:,');
  // an image fits the page
  const fits = await bookPage(page).evaluate(doc => {
    const c = doc.getBoundingClientRect();
    return [...doc.querySelectorAll('img')].every(i => i.getBoundingClientRect().height <= c.height);
  });
  expect(fits).toBe(true);
});

test('text is decoded and marked up as the book has it', async ({ page }) => {
  await start(page);
  const body = `<h1>Heading One</h1><h2>Heading Two</h2>
<p id="x1">Tom &amp; Jerry &lt;3 &#233;t&#xE9; caf&eacute; &#x201C;q&#x201D; <b>bold</b> <i>it</i> <em>em</em> <strong>strong</strong> <code>code</code> H<sub>2</sub>O x<sup>2</sup></p>
<hr/>
<blockquote><p>Quoted</p></blockquote>
<ul><li>one</li><li>two</li></ul>
<table><tr><td colspan="2">cell</td></tr></table>
<p dir="rtl" lang="ar" title="tip">مرحبا</p>`;
  await readBook(page, { title: 'Markup', author: 'Bot', rawChapters: [{ body }] });
  const p = bookPage(page).locator('p').first();
  await expect(p).toContainText('Tom & Jerry <3 été café “q”');
  for (const tag of ['b', 'i', 'em', 'strong', 'code', 'sub', 'sup']) {
    await expect(p.locator(tag)).toHaveCount(1);
  }
  await expect(bookPage(page).locator('h1')).toHaveText('Heading One');
  await expect(bookPage(page).locator('h2')).toHaveText('Heading Two');
  await expect(bookPage(page).locator('hr')).toHaveCount(1);
  expect(await bookPage(page).locator('hr').evaluate(e => e.getBoundingClientRect().width > 0)).toBe(true);
  await expect(bookPage(page).locator('blockquote p')).toHaveText('Quoted');
  await expect(bookPage(page).getByRole('listitem')).toHaveCount(2);
  await expect(bookPage(page).locator('td[colspan="2"]')).toHaveText('cell');
  const rtl = bookPage(page).locator('p[dir="rtl"]');
  await expect(rtl).toHaveAttribute('lang', 'ar');
  await expect(rtl).toHaveAttribute('title', 'tip');
  // inline elements stay inline
  expect(await p.locator('b').evaluate(e => getComputedStyle(e).display)).toBe('inline');
});

test('links: out of the book open outside it, inside it jump and can go back', async ({ page }) => {
  await start(page);
  const filler = Array.from({ length: 25 }, (_, k) => `<p>Filler ${k} ` + 'lorem ipsum dolor sit amet '.repeat(12) + '</p>').join('');
  await readBook(page, {
    title: 'Links', author: 'Bot',
    rawChapters: [
      { body: '<p>See <a href="chapter2.xhtml#far">the far place</a> or <a href="https://example.com/">the web</a>.</p>' + filler },
      { body: filler + '<p id="far">FAR-TARGET</p>' },
    ],
  });
  const out = bookPage(page).getByRole('link', { name: 'the web' });
  await expect(out).toHaveAttribute('href', 'https://example.com/');
  await expect(out).toHaveAttribute('target', '_blank');
  await expect(out).toHaveAttribute('rel', /noopener/);
  await bookPage(page).getByRole('link', { name: 'the far place' }).click();
  await expect(chapterTitle(page)).toHaveText('Chapter 2');
  expect(await visibleText(page)).toContain('FAR-TARGET');
  await expect(jumpBack(page)).toBeVisible();
  await jumpBack(page).click();
  await expect(chapterTitle(page)).toHaveText('Chapter 1');
  expect(await place(page)).toMatchObject({ ch: 1, p: 1 });
  // the link is reached and followed from the keyboard too
  const inside = bookPage(page).getByRole('link', { name: 'the far place' });
  await inside.focus();
  await expect(inside).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(chapterTitle(page)).toHaveText('Chapter 2');
  expect(await visibleText(page)).toContain('FAR-TARGET');
});

test('a book read right to left turns the other way', async ({ page }) => {
  await start(page);
  await readBook(page, { ...book('Right To Left', 2), rtl: true });
  expect(await bookPage(page).locator('p').first().evaluate(e => getComputedStyle(e).direction)).toBe('rtl');
  await page.keyboard.press('ArrowLeft');
  await expect.poll(async () => (await place(page)).p).toBe(2);
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(1);
});

test('a book\'s own font is used when chosen', async ({ page }) => {
  await start(page);
  const font = (await import('node:fs')).readFileSync('assets/fonts/inter-latin.woff2');
  await readBook(page, {
    ...book('Own Font', 1, 5),
    extraFiles: [{ name: 'fonts/own.woff2', data: font, mediaType: 'font/woff2' }],
  });
  await openSettings(page);
  await page.getByRole('button', { name: 'Book', exact: true }).click();
  // the page is set in a face that is neither bundled font, and that face
  // is one the book brought, loaded
  const family = () => bookPage(page).locator('p').first().evaluate(e => getComputedStyle(e).fontFamily.split(',')[0].trim().replace(/"/g, ''));
  await expect.poll(family).not.toMatch(/^(Literata|Inter)$/);
  const f = await family();
  await expect.poll(() => page.evaluate(f => [...document.fonts].some(x => x.family.replace(/"/g, '') === f && x.status === 'loaded'), f)).toBe(true);
});

test('a card shows how far the book has been read', async ({ page }) => {
  await start(page);
  await readBook(page, book('Progress', 2));
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  await toLibrary(page);
  await expect(card(page, 'Progress')).toContainText(/\d+%/);
  expect(await card(page, 'Progress').innerText()).not.toContain('New');
});
