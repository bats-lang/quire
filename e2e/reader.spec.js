// Reading: turning pages every way the reader offers, chapters, the
// bars, keeping the place, and what a chapter's XHTML becomes on the
// page.

import { test, expect } from '@playwright/test';
import zlib from 'node:zlib';
import { TINY_PNG } from './create-epub.js';
import {
  start, openBook, readBook, place, placeChanged, startsOnPage, onPage, visibleText, toLibrary,
  showChrome, chapters, card, bookPage, chapterTitle, control, jumpBack, librarySearch, openSettings, reload, dialog,
  importFiles, indicator, chapterBody,
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
  await reload(page);
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
  await reload(page);
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

// A real book: its pages begin inside paragraphs, and not every number
// the reader gives its content is an element (a text node's is not), so
// the place is kept by an element that begins on the page
test('a real book keeps its place when reopened, at a new type size and at a new window size', async ({ page }) => {
  await start(page);
  await importFiles(page, ['test/fixtures/conan-stories.epub'], 1);
  await openBook(page, 'Gods of the North');
  // the cover, which the contents do not name, is "Chapter 1"; the story
  // after it is named by its title
  while ((await place(page)).ch === 1) await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe('GODS OF THE NORTH');
  for (let k = 0; k < 6; k++) {
    const before = await place(page);
    await page.keyboard.press('ArrowRight');
    await placeChanged(page, before);
  }
  const at = await place(page);
  const top = (await startsOnPage(page))[0];
  expect(top, 'a paragraph begins on the page').toBeTruthy();
  await toLibrary(page);
  await openBook(page, 'Gods of the North');
  await expect.poll(() => place(page)).toEqual(at);
  expect(await onPage(page, top)).toBe(true);
  await openSettings(page);
  await page.getByRole('slider', { name: 'Size' }).fill('24');
  await page.keyboard.press('Escape');
  await expect.poll(() => onPage(page, top)).toBe(true);
  expect((await place(page)).p).toBeGreaterThan(1);
  const size = page.viewportSize();
  await page.setViewportSize({ width: size.height, height: size.width });
  await expect.poll(() => onPage(page, top)).toBe(true);
  expect((await place(page)).p).toBeGreaterThan(1);
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
  await reload(page);
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

test('a note\'s reference opens the note over the page, which can be gone to', async ({ page }) => {
  await start(page);
  const filler = Array.from({ length: 25 }, (_, k) => `<p>Filler ${k} ` + 'lorem ipsum dolor sit amet '.repeat(12) + '</p>').join('');
  await readBook(page, {
    title: 'Notes', author: 'Bot',
    rawChapters: [
      { body: '<p>A claim<a epub:type="noteref" href="chapter3.xhtml#n1">1</a>, an aside<a epub:type="noteref" href="#n2">2</a>' +
          ' and a lost one<a role="doc-noteref" href="chapter2.xhtml#nowhere">3</a>.</p>' + filler +
          '<aside epub:type="footnote" id="n2"><p>Same-chapter note &amp; its words.</p></aside>' },
      { body: filler },
      { body: '<h1>Notes</h1><aside epub:type="endnote" id="n1"><p><a href="chapter1.xhtml">1</a> The endnote\'s own   words.</p>' +
          '<p>Its second paragraph.</p></aside>' },
    ],
  });
  const note = dialog(page, 'Footnote');
  const at = await place(page);
  // an endnote in another chapter: shown, and the page stays
  await bookPage(page).getByRole('link', { name: '1', exact: true }).click();
  await expect(note).toBeVisible();
  await expect(note).toContainText("1 The endnote's own words. Its second paragraph.");
  expect(await place(page)).toEqual(at);
  await note.getByRole('button', { name: 'Close', exact: true }).click();
  await expect(note).toBeHidden();
  await expect(bookPage(page)).toBeFocused();
  // a footnote in the same chapter, its reference decoded, closed with Escape
  await bookPage(page).getByRole('link', { name: '2', exact: true }).click();
  await expect(note).toContainText('Same-chapter note & its words.');
  await page.keyboard.press('Escape');
  await expect(note).toBeHidden();
  expect(await place(page)).toEqual(at);
  // from the keyboard, then gone to, with the way back
  const ref = bookPage(page).getByRole('link', { name: '1', exact: true });
  await ref.focus();
  await page.keyboard.press('Enter');
  await expect(note).toBeVisible();
  await note.getByRole('button', { name: 'Go to note' }).click();
  await expect(note).toBeHidden();
  await expect(chapterTitle(page)).toHaveText('Chapter 3');
  expect(await visibleText(page)).toContain("The endnote's own");
  await expect(jumpBack(page)).toBeVisible();
  await jumpBack(page).click();
  await expect.poll(() => place(page)).toEqual(at);
  // a reference to a note that is not there is followed as a link
  await bookPage(page).getByRole('link', { name: '3', exact: true }).click();
  await expect(chapterTitle(page)).toHaveText('Chapter 2');
  await expect(note).toBeHidden();
});

/** A w by h PNG of one grey */
function png(w, h) {
  const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
  const crc = b => { let c = 0xffffffff; for (const x of b) c = crcTable[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]);
    const c = Buffer.alloc(4); c.writeUInt32BE(crc(td));
    return Buffer.concat([len, td, c]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 0;
  const raw = Buffer.alloc((w + 1) * h, 128);
  for (let y = 0; y < h; y++) raw[y * (w + 1)] = 0;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

test('an image is shown full screen from a tap on it between the sides, or a long press', async ({ page }) => {
  await start(page);
  await readBook(page, {
    title: 'Viewer', author: 'Bot',
    rawChapters: [{ body: '<p><img src="images/p.png" alt="the map"/></p>' + chapterBody(1, 10) }],
    extraEntries: [{ name: 'OEBPS/images/p.png', data: png(64, 64), store: true }],
  });
  await page.keyboard.press('t');
  const viewer = dialog(page, 'Image');
  const pic = bookPage(page).getByRole('img', { name: 'the map' });
  await expect.poll(() => pic.evaluate(i => i.naturalWidth)).toBe(64);
  const at = await place(page);
  await pic.click();
  await expect(viewer).toBeVisible();
  await expect.poll(() => viewer.locator('img').evaluate(i => i.complete && i.naturalWidth)).toBe(64);
  // the page is not turned (the chapter's page count may settle as its
  // image loads, which is not a turn)
  expect(await place(page)).toMatchObject({ ch: at.ch, p: at.p });
  await viewer.getByRole('button', { name: 'Close' }).click();
  await expect(viewer).toBeHidden();
  await expect(bookPage(page)).toBeFocused();
  // a long press (here a right click) too; Escape closes it
  await pic.click({ button: 'right' });
  await expect(viewer).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(viewer).toBeHidden();
  // a tap on the page's side still turns it
  const box = await bookPage(page).boundingBox();
  await page.mouse.click(box.x + box.width * 0.9, box.y + box.height * 0.7);
  await expect.poll(async () => (await place(page)).p).toBe(at.p + 1);
  await expect(viewer).toBeHidden();
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

test('the page indicator names the chapter, and a long title is cut before the page numbers are', async ({ page }) => {
  await start(page);
  const long = 'An Exceedingly Long Chapter Title That Goes On and On Past Any Phone';
  await readBook(page, {
    title: 'Titled', author: 'Reader Tests', rawChapters: chapters(2),
    toc: [{ label: long, href: 'chapter1.xhtml' }, { label: 'Short', href: 'chapter2.xhtml' }],
  });
  await showChrome(page);
  expect(await place(page)).toMatchObject({ ch: long, p: 1 });
  const numbers = indicator(page).getByText(/· page \d+ of \d+ in chapter/);
  const box = await numbers.boundingBox();
  const bar = await control(page, 'Next page').boundingBox();
  expect(box.x + box.width).toBeLessThanOrEqual(bar.x + 1);
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe('Short');
});

test('while the bars are hidden, a footer says the chapter, the pages left in it and how far into the book the page is', async ({ page }) => {
  await start(page);
  await readBook(page, book('Footer', 2));
  const readout = page.locator('[aria-hidden="true"]').getByText(/· (\d+ pages? left in chapter|last page in chapter)$/);
  const ofBook = page.locator('[aria-hidden="true"]').getByText(/· (<1|\d+)% of book$/);
  // the bars are up when a book opens; the footer is under them
  await showChrome(page);
  await expect(readout).toBeHidden();
  await page.keyboard.press('t');
  await expect(readout).toBeVisible();
  const { t } = await place(page);
  // each number names its scope, on one line
  await expect(readout).toHaveText(`· ${t - 1} pages left in chapter`);
  await expect(ofBook).toHaveText('· 0% of book');
  await expect(readout.locator('..')).toHaveText(`Chapter 1\u00a0· ${t - 1} pages left in chapter\u00a0· 0% of book`);
  // it keeps up with the page, and is not read out twice (the page
  // indicator says the same)
  await page.keyboard.press('ArrowRight');
  await expect(readout).toHaveText(`· ${t - 2} pages left in chapter`);
  await page.keyboard.press('End');
  await expect(readout).toHaveText('· last page in chapter');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  const pct = +(/(\d+)%/.exec(await ofBook.textContent())[1]);
  expect(pct).toBeGreaterThanOrEqual(45);
  expect(pct).toBeLessThanOrEqual(55);
  expect(await indicator(page).count()).toBe(1);
  expect(await readout.evaluate(e => e.closest('[aria-hidden="true"]') !== null)).toBe(true);
});

test('the page indicator says which page of the chapter\'s it is', async ({ page }) => {
  await start(page);
  await readBook(page, book('Indicated', 2));
  const { t } = await place(page);
  await expect(indicator(page)).toHaveText(`Chapter 1\u00a0· page 1 of ${t} in chapter`);
});

test('a tap on the footer\'s readout shows the next one, which is kept, and turns no page', async ({ page }) => {
  await start(page);
  // a cover before the contents' first entry, then two chapters
  await readBook(page, {
    title: 'Readouts', author: 'Reader Tests', rawChapters: chapters(3),
    toc: [{ label: 'One', href: 'chapter2.xhtml' }, { label: 'Two', href: 'chapter3.xhtml' }],
  });
  await page.keyboard.press('t');
  const readout = page.locator('[aria-hidden="true"]').getByText(/· (\d+ pages? left in chapter|page \d+ of \d+ in chapter|(before )?chapter \d+ of \d+)$/);
  const { t } = await place(page);
  await expect(readout).toHaveText(`· ${t - 1} pages left in chapter`);
  await readout.click();
  await expect(readout).toHaveText(`· page 1 of ${t} in chapter`);
  expect(await place(page)).toMatchObject({ p: 1 });
  // the chapters are the contents' entries: the cover is before them
  await readout.click();
  await expect(readout).toHaveText('· before chapter 1 of 2');
  // the times are not offered before the reading speed is known
  await readout.click();
  await expect(readout).toHaveText(`· ${t - 1} pages left in chapter`);
  await readout.click();
  await readout.click();
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe('One');
  await expect(readout).toHaveText('· chapter 1 of 2');
  // the choice is kept
  await reload(page);
  await expect(bookPage(page)).toBeVisible();
  await page.keyboard.press('t');
  await expect(readout).toHaveText('· chapter 1 of 2');
  // a tap beside it is the page's: in the middle, it brings the bars up
  const title = readout.locator('..').locator('span').first();
  const box = await title.boundingBox();
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await expect(readout).toBeHidden();
});

test('the book\'s percentage is never 0% once reading has begun', async ({ page }) => {
  await start(page);
  // a short first chapter before a long one: its second page is well
  // under 1% of the book
  await readBook(page, {
    title: 'Begun', author: 'Reader Tests',
    rawChapters: [{ body: chapterBody(1, 6) }, { body: chapterBody(2, 1200) }],
  });
  await page.keyboard.press('t');
  const ofBook = page.locator('[aria-hidden="true"]').getByText(/· (<1|\d+)% of book$/);
  await expect(ofBook).toHaveText('· 0% of book');
  const before = await place(page);
  await page.keyboard.press('ArrowRight');
  await placeChanged(page, before);
  await expect(ofBook).toHaveText('· <1% of book');
});

test('the time the chapter and the book take to finish is learned from the reader\'s own speed', async ({ page }) => {
  await page.clock.install();
  await start(page);
  await readBook(page, book('Timed', 3, 60));
  await page.keyboard.press('t');
  const readout = page.locator('[aria-hidden="true"]').getByText(/· (\d+ pages? left in chapter|page \d+ of \d+ in chapter|chapter \d+ of \d+|.* min left in (chapter|book))$/);
  // not guessed before it is known: the readouts are the pages and the
  // chapter only
  for (let k = 0; k < 3; k++) {
    await expect(readout).not.toContainText('min');
    await readout.click();
  }
  await expect(readout).toContainText('pages left in chapter');
  // a page a minute, for a dozen pages
  for (let k = 0; k < 12; k++) {
    const before = await place(page);
    await page.clock.fastForward('01:00');
    await page.keyboard.press('ArrowRight');
    await placeChanged(page, before);
  }
  const { p, t } = await place(page);
  const left = t - p;
  await expect(readout).toHaveText(`· ${left} page${left === 1 ? '' : 's'} left in chapter`);
  for (let k = 0; k < 3; k++) await readout.click();
  await expect(readout).toHaveText(`· ${left} min left in chapter`);
  await readout.click();
  await expect(readout).toHaveText(/· (\d+ h )?\d+ min left in book$/);
  await readout.click();
  await expect(readout).toContainText('pages left in chapter');
  for (let k = 0; k < 3; k++) await readout.click();
  // the book's time, with the bars up, by the scrubber
  await page.keyboard.press('t');
  await expect(page.getByText(/^\d+% · (\d+ h )?\d+ min left$/)).toBeVisible();
  // a long pause is not reading: the speed stays a page a minute
  await page.keyboard.press('t');
  const before = await place(page);
  await page.clock.fastForward('30:00');
  await page.keyboard.press('ArrowRight');
  await placeChanged(page, before);
  const at = await place(page);
  await expect(readout).toHaveText(`· ${at.t - at.p} min left in chapter`);
});

test('the page has the book\'s language, or its chapter\'s, so it is hyphenated and read out in it', async ({ page }) => {
  await start(page);
  const lang = () => bookPage(page).getAttribute('lang');
  await readBook(page, {
    title: 'Livre', author: 'Reader Tests', language: 'fr',
    rawChapters: [...chapters(1), { ...chapters(2)[1], lang: 'de-CH' }, ...chapters(3).slice(2)],
  });
  expect(await lang()).toBe('fr');
  // a chapter's own language (on its html element) is that chapter's
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  expect(await lang()).toBe('de-CH');
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(3);
  expect(await lang()).toBe('fr');
  // a book that names no language is not taken for English
  await toLibrary(page);
  await readBook(page, { title: 'Unnamed', author: 'Reader Tests', language: null, rawChapters: chapters(1) });
  expect(await lang()).toBe('und');
});

test('taps on the page follow the chosen zones: sides, forward or one hand', async ({ page }) => {
  await start(page);
  await readBook(page, book('Zones', 1, 40));
  await page.keyboard.press('t');
  const tap = async (fx, fy) => {
    const box = await bookPage(page).boundingBox();
    await page.mouse.click(box.x + box.width * fx, box.y + box.height * fy);
  };
  const turned = async (fx, fy, by) => {
    const before = await place(page);
    await tap(fx, fy);
    await expect.poll(async () => (await place(page)).p).toBe(before.p + by);
  };
  const bars = () => control(page, 'Previous page').isVisible();
  // sides: the middle brings up the bars
  await turned(0.9, 0.5, 1);
  await tap(0.5, 0.5);
  await expect.poll(bars).toBe(true);
  // forward: the middle turns on, the left quarter back, the top the bars
  await openSettings(page);
  await dialog(page, 'Typography and theme').getByRole('group', { name: 'What a tap on the page does' })
    .getByRole('button', { name: 'Forward' }).click();
  await page.keyboard.press('Escape');
  await page.keyboard.press('t');
  await expect.poll(bars).toBe(false);
  await turned(0.5, 0.5, 1);
  await turned(0.1, 0.5, -1);
  await tap(0.5, 0.03);
  await expect.poll(bars).toBe(true);
  // one hand: the top third back, the bottom third on, the middle the bars
  await openSettings(page);
  await dialog(page, 'Typography and theme').getByRole('button', { name: 'One hand' }).click();
  await page.keyboard.press('Escape');
  await page.keyboard.press('t');
  await expect.poll(bars).toBe(false);
  await turned(0.5, 0.9, 1);
  await turned(0.5, 0.1, -1);
  await tap(0.5, 0.5);
  await expect.poll(bars).toBe(true);
});

test('the volume keys turn the page when the reader chooses, and are the volume\'s otherwise', async ({ page }) => {
  await start(page);
  await readBook(page, book('Volume', 1, 30));
  // Playwright has no volume keys: the keydown a browser that gives them
  // to the page would send
  const press = key => page.evaluate(k => document.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true })), key);
  const at = await place(page);
  // the volume's, to begin with
  await press('AudioVolumeDown');
  expect(await place(page)).toEqual(at);
  await openSettings(page);
  const vol = dialog(page, 'Typography and theme').getByRole('group', { name: 'Volume keys turn the page' });
  await expect(vol.getByRole('button', { name: 'Volume' })).toHaveAttribute('aria-pressed', 'true');
  await vol.getByRole('button', { name: 'Turn pages' }).click();
  await page.keyboard.press('Escape');
  await press('AudioVolumeDown');
  await expect.poll(async () => (await place(page)).p).toBe(at.p + 1);
  await press('AudioVolumeUp');
  await expect.poll(async () => (await place(page)).p).toBe(at.p);
});

test('the t key shows and hides the bars', async ({ page }) => {
  await start(page);
  await readBook(page, book('Toggle', 1, 10));
  const prev = control(page, 'Previous page');
  await page.keyboard.press('Escape'); // the bars shown on opening
  await expect(prev).toBeHidden();
  await page.keyboard.press('t');
  await expect(prev).toBeVisible();
  await page.keyboard.press('t');
  await expect(prev).toBeHidden();
});

test('the place is kept when the app is hidden and then closed', async ({ page }) => {
  await start(page);
  await readBook(page, book('Hidden Away', 2));
  for (let k = 0; k < 2; k++) await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(3);
  const at = await place(page);
  // the tab is hidden (another app), then the page is gone without going back to the library
  await page.evaluate(() => {
    Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await reload(page);
  // back in the book, on its page, without the library in between
  await expect(bookPage(page)).toBeVisible();
  await expect(indicator(page)).toContainText('in chapter');
  await expect.poll(() => place(page)).toEqual(at);
});

test('a reload in the middle of a book comes back to that page, and one in the library to the library', async ({ page }) => {
  await start(page);
  await readBook(page, book('Reloaded', 3, 30));
  for (let k = 0; k < 7; k++) {
    const before = await place(page);
    await page.keyboard.press('ArrowRight');
    await placeChanged(page, before);
  }
  const at = await place(page);
  const top = (await startsOnPage(page))[0];
  await reload(page);
  await expect(bookPage(page)).toBeVisible();
  await expect(indicator(page)).toContainText('in chapter');
  await expect.poll(() => place(page)).toEqual(at);
  expect(await onPage(page, top)).toBe(true);
  // the library is never shown on the way
  await expect(librarySearch(page)).toBeHidden();
  // again, straight after
  await reload(page);
  await expect(indicator(page)).toContainText('in chapter');
  await expect.poll(() => place(page)).toEqual(at);
  // left for the library: a reload stays there
  await toLibrary(page);
  await reload(page);
  await expect(librarySearch(page)).toBeVisible();
  await expect(bookPage(page)).toBeHidden();
});

test('a reload in a real book comes back to its page', async ({ page }) => {
  await start(page);
  await importFiles(page, ['test/fixtures/conan-stories.epub'], 1);
  await openBook(page, 'Gods of the North');
  while ((await place(page)).ch === 1) await page.keyboard.press('ArrowRight');
  for (let k = 0; k < 5; k++) {
    const before = await place(page);
    await page.keyboard.press('ArrowRight');
    await placeChanged(page, before);
  }
  const at = await place(page);
  const top = (await startsOnPage(page))[0];
  await reload(page);
  await expect(indicator(page)).toContainText('in chapter');
  // the same page, with the same text at its top (the chapter's page
  // count may settle once its illustration has loaded)
  await expect.poll(async () => { const { ch, p } = await place(page); return { ch, p }; }).toEqual({ ch: at.ch, p: at.p });
  expect(await onPage(page, top)).toBe(true);
});

test('the screen is kept awake while a book is open, and again when the app comes back', async ({ page }) => {
  // The Screen Wake Lock API, counting the locks the app holds; like the
  // browser's, a lock is released when the page is hidden
  await page.addInitScript(() => {
    const w = window.__wake = { held: 0, requests: 0, live: [] };
    const take = () => {
      const on = [];
      const lock = {
        released: false,
        addEventListener: (type, f) => { if (type === 'release') on.push(f); },
        release: async () => {
          if (lock.released) return;
          lock.released = true;
          w.held--;
          w.live = w.live.filter(l => l !== lock);
          on.forEach(f => f());
        },
      };
      w.held++;
      w.live.push(lock);
      return lock;
    };
    Object.defineProperty(navigator, 'wakeLock', {
      configurable: true,
      value: { request: async type => { w.requests++; if (type !== 'screen') throw new Error(type); return take(); } },
    });
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'hidden') w.live.slice().forEach(l => l.release());
    });
  });
  const held = () => page.evaluate(() => window.__wake.held);
  const errors = await start(page);
  expect(await held()).toBe(0);
  await readBook(page, book('Awake', 2));
  await expect.poll(held).toBe(1);
  // hidden, the browser lets it go; shown again, the app takes it again
  const show = v => page.evaluate(state => {
    Object.defineProperty(document, 'visibilityState', { value: state, configurable: true });
    document.dispatchEvent(new Event('visibilitychange'));
  }, v);
  await show('hidden');
  await expect.poll(held).toBe(0);
  await show('visible');
  await expect.poll(held).toBe(1);
  // back in the library the screen may sleep, and coming back leaves it so
  await toLibrary(page);
  await expect.poll(held).toBe(0);
  await show('hidden');
  await show('visible');
  expect(await held()).toBe(0);
  expect(await page.evaluate(() => window.__wake.requests)).toBe(2);
  expect(errors).toEqual([]);
});

test.describe('on a touch screen', () => {
  test.use({ hasTouch: true });

  // A pointer's path, as touch pointer events, one move per step, ms
  // apart: the gestures recognizer classifies them in the app
  const drag = (page, points, ms, { cancel = false, id = 7 } = {}) =>
    bookPage(page).evaluate(async (el, [points, ms, cancel, id]) => {
      const ev = (type, [x, y]) => el.dispatchEvent(new PointerEvent(type, {
        bubbles: true, pointerId: id, pointerType: 'touch', isPrimary: true, clientX: x, clientY: y,
      }));
      const wait = (t) => new Promise((r) => setTimeout(r, t));
      ev('pointerdown', points[0]);
      for (const p of points.slice(1)) { await wait(ms); ev('pointermove', p); }
      await wait(ms);
      ev(cancel ? 'pointercancel' : 'pointerup', points[points.length - 1]);
      await wait(50);
    }, [points, ms, cancel, id]);
  const across = (x0, x1, y, n) =>
    Array.from({ length: n + 1 }, (_, i) => [x0 + ((x1 - x0) * i) / n, y]);

  test('a swipe turns the page, and a short, upright, edge or cancelled one does not', async ({ page }) => {
    await start(page);
    await readBook(page, book('Swiped', 1, 20));
    const box = await bookPage(page).boundingBox();
    const y = box.y + box.height / 2;
    const mid = box.x + box.width / 2;
    // a flick to the left: the next page
    await drag(page, across(mid + 60, mid - 60, y, 4), 16);
    await expect.poll(async () => (await place(page)).p).toBe(2);
    // a slow, long drag to the right: back
    await drag(page, across(mid - 80, mid + 80, y, 8), 60);
    await expect.poll(async () => (await place(page)).p).toBe(1);
    // too short and slow
    await drag(page, across(mid + 20, mid - 20, y, 4), 80);
    // more down than across
    await drag(page, [[mid, y - 150], [mid + 20, y - 50], [mid + 40, y + 50], [mid + 60, y + 150]], 16);
    // from the screen's left edge (the system's back gesture)
    await drag(page, across(5, 205, y, 4), 16);
    // cancelled by the system mid-drag
    await drag(page, across(mid + 100, mid - 100, y, 4), 16, { cancel: true });
    await page.waitForTimeout(300);
    expect((await place(page)).p).toBe(1);
  });

  test('the page follows the finger, and goes back when the drag is cancelled', async ({ page }) => {
    await start(page);
    await readBook(page, book('Followed', 1, 20));
    const box = await bookPage(page).boundingBox();
    const y = box.y + box.height / 2;
    const mid = box.x + box.width / 2;
    const offsets = await bookPage(page).evaluate(async (el, [mid, y]) => {
      const ev = (type, x) => el.dispatchEvent(new PointerEvent(type, {
        bubbles: true, pointerId: 9, pointerType: 'touch', isPrimary: true, clientX: x, clientY: y,
      }));
      const frame = () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
      const rest = el.scrollLeft;
      ev('pointerdown', mid + 60);
      for (const dx of [20, 40, 60]) { await frame(); ev('pointermove', mid + 60 - dx); }
      await frame(); await frame();
      const held = el.scrollLeft;
      ev('pointercancel', mid);
      await frame();
      return [rest, held, el.scrollLeft];
    }, [mid, y]);
    // dragged 60 px to the left: the next page shows that much
    expect(offsets[1] - offsets[0]).toBeGreaterThan(30);
    expect(offsets[2]).toBe(offsets[0]);
    expect((await place(page)).p).toBe(1);
  });
});

test('a mouse drag over the page selects text and does not turn it', async ({ page }) => {
  await start(page);
  await readBook(page, book('Dragged', 1, 20));
  const box = await bookPage(page).boundingBox();
  const y = box.y + box.height / 3;
  await page.mouse.move(box.x + box.width / 2 + 100, y);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width / 2 - 100, y, { steps: 8 });
  await page.mouse.up();
  await page.waitForTimeout(300);
  expect((await place(page)).p).toBe(1);
  expect(await page.evaluate(() => window.getSelection().toString().length)).toBeGreaterThan(0);
});

test('Escape closes the overlay opened last, one at a time', async ({ page }) => {
  await start(page);
  await readBook(page, { title: 'Layered', author: 'L', rawChapters: chapters(1) });
  await openSettings(page);
  // the search panel opens over the typography sheet
  await page.keyboard.press('/');
  const search = dialog(page, 'Search in book');
  const sheet = dialog(page, 'Typography and theme');
  await expect(search).toBeVisible();
  await expect(sheet).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(search).toBeHidden();
  await expect(sheet).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(sheet).toBeHidden();
});
