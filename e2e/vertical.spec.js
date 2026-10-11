// Vertical writing: a Japanese (Chinese, Korean) book read right to left
// is set vertically, as Readium sets it from its OPF (the book's own CSS
// is not used). Its columns follow the inline axis, down the page, so
// its pages go down: a turn scrolls one page height.

import { test, expect } from './fixtures.js';
import {
  start, importFiles, epubFile, openBook, readBook, toLibrary, reload, bookPage, dialog,
  place, indicator, chapters, japaneseChapters,
  readingSettings, openReadingSettings, expectBarFollows, marks, selectionButton,
} from './helpers.js';

const verticalBook = (title) => ({ title, author: 'Vertical Tests', language: 'ja', rtl: true, rawChapters: japaneseChapters(2, 40) });

const sheet = page => dialog(page, 'Reading settings');

/** The page's scroll down, and its height */
const scroll = page => bookPage(page).evaluate(e => ({ top: e.scrollTop, height: e.clientHeight }));

/** The text of the paragraphs and headings in view: down the page,
    those whose boxes cross the page's height */
const visibleText = page => bookPage(page).evaluate(doc => {
  const c = doc.getBoundingClientRect();
  return [...doc.querySelectorAll('p, h1')]
    .filter(e => [...e.getClientRects()].some(r => r.bottom > c.top + 1 && r.top < c.bottom - 1))
    .map(e => e.textContent.slice(0, 12)).join('\n');
});

// quire#359: a precondition, not a skip: this spec's shots of a
// vertical book are of empty boxes where no CJK font is installed (the
// canvas draws a Han character and a code point no font has the same
// width), so a machine without one fails here, naming the cause
test('a font with Japanese characters is installed, or the vertical book is drawn as empty boxes', async ({ page }) => {
  await start(page);
  const drawn = await page.evaluate(() => {
    const context = document.createElement('canvas').getContext('2d');
    context.font = '32px sans-serif';
    return { han: context.measureText('日本語').width, missing: context.measureText('\uFFFF\uFFFF\uFFFF').width };
  });
  expect(drawn.han, 'a Han character has a glyph of its own, not the missing-glyph box').not.toBe(drawn.missing);
});

test('a Japanese book read right to left is set vertically, its pages going down', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, verticalBook('縦書き'));
  const style = await bookPage(page).evaluate(e => ({ mode: getComputedStyle(e).writingMode, direction: getComputedStyle(e).direction, orientation: getComputedStyle(e).textOrientation }));
  // Latin and digits are turned, as JLREQ has them (quire#391)
  expect(style).toEqual({ mode: 'vertical-rl', direction: 'ltr', orientation: 'mixed' });
  // the bottom bar follows its reading axis, from the right (quire#359)
  await expectBarFollows(page, true);
  const at = await place(page);
  expect(at.p).toBe(1);
  expect(at.t).toBeGreaterThan(1);
  const before = await scroll(page);
  expect(before.top).toBe(0);
  const shown = await visibleText(page);
  // Next: exactly one page height down, and other text
  await page.keyboard.press('ArrowLeft');
  await expect.poll(async () => (await place(page)).p).toBe(2);
  const after = await scroll(page);
  expect(after.top - before.top).toBe(before.height);
  expect(await visibleText(page)).not.toBe(shown);
  // a tap on the left side turns on, as in any book read right to left
  const box = await bookPage(page).boundingBox();
  await page.mouse.click(box.x + 10, box.y + box.height / 2);
  await expect.poll(async () => (await place(page)).p).toBe(3);
  expect((await scroll(page)).top).toBe(2 * before.height);
  // and the right side back
  await page.mouse.click(box.x + box.width - 10, box.y + box.height / 2);
  await expect.poll(async () => (await place(page)).p).toBe(2);
  expect(errors).toEqual([]);
});

test('a book set vertically is not offered the layout\'s settings; a horizontal one is', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile(verticalBook('縦組み')), epubFile({ title: 'Across', author: 'Vertical Tests', rawChapters: chapters(1) })], 2);
  await openBook(page, '縦組み');
  await openReadingSettings(page, 'Page');
  await expect(sheet(page).getByRole('group', { name: 'Layout' })).toBeHidden();
  await expect(readingSettings(page).getByRole('group', { name: 'Pages on screen' })).toBeHidden();
  await expect(readingSettings(page).getByRole('slider', { name: 'Margins' })).toBeHidden();
  await expect(readingSettings(page).getByRole('button', { name: 'Justify text', exact: true })).toBeHidden();
  await expect(readingSettings(page).getByRole('button', { name: 'Hyphenation', exact: true })).toBeHidden();
  await page.keyboard.press('Escape');
  await toLibrary(page);
  await openBook(page, 'Across');
  await openReadingSettings(page, 'Page');
  await expect(sheet(page).getByRole('group', { name: 'Layout' })).toBeVisible();
  await expect(readingSettings(page).getByRole('group', { name: 'Pages on screen' })).toBeVisible();
  await expect(readingSettings(page).getByRole('slider', { name: 'Margins' })).toBeVisible();
  await expect(readingSettings(page).getByRole('button', { name: 'Justify text', exact: true })).toBeVisible();
  await expect(readingSettings(page).getByRole('button', { name: 'Hyphenation', exact: true })).toBeVisible();
  // and the horizontal book is not set vertically
  expect(await bookPage(page).evaluate(e => getComputedStyle(e).writingMode)).toBe('horizontal-tb');
  expect(await bookPage(page).evaluate(e => getComputedStyle(e).textOrientation)).toBe('mixed');
});

test('set vertically, the space after a paragraph is beside it, not below it, and its row is offered', async ({ page }) => {
  await start(page);
  // short paragraphs, so the first two are on the first page whatever
  // the font's measures: a long one can fill the page, the next on
  // the page after it
  const shortParagraphs = Array.from({ length: 8 }, (_, k) => `<p>短い段落 ${k}。吾輩は猫である。</p>`).join('');
  await readBook(page, { ...verticalBook('段落の間'), chapters: 1, rawChapters: [{ body: `<h1>第1章</h1>${shortParagraphs}` }] });
  const boxes = await bookPage(page).evaluate(doc => {
    const [first, second] = [...doc.querySelectorAll('p')];
    const a = first.getClientRects()[first.getClientRects().length - 1];
    const b = second.getClientRects()[0];
    const style = getComputedStyle(first);
    return {
      firstLeft: a.left, secondRight: b.right,
      spacing: parseFloat(style.marginLeft), below: parseFloat(style.marginBottom),
    };
  });
  // the paragraph spacing (0.8 em by default) is above zero, beside the
  // paragraph (its left side, in vertical-rl), and nothing is below it
  expect(boxes.spacing).toBeGreaterThan(0);
  expect(boxes.below).toBe(0);
  expect(boxes.secondRight).toBeLessThanOrEqual(boxes.firstLeft - boxes.spacing + 0.5);
  await openReadingSettings(page, 'Look');
  await expect(readingSettings(page).getByRole('slider', { name: 'Paragraph spacing' })).toBeVisible();
});

test('a book set vertically is paged even when the layout is scrolled', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile(verticalBook('段組')), epubFile({ title: 'Scrolled', author: 'Vertical Tests', rawChapters: chapters(1) })], 2);
  await openBook(page, 'Scrolled');
  await openReadingSettings(page, 'Page');
  await sheet(page).getByRole('group', { name: 'Layout' }).getByRole('button', { name: 'Scroll', exact: true }).click();
  await page.keyboard.press('Escape');
  await toLibrary(page);
  await openBook(page, '段組');
  const at = await place(page);
  expect(at.t).toBeGreaterThan(1);
  const before = await scroll(page);
  await page.keyboard.press('ArrowLeft');
  await expect.poll(async () => (await place(page)).p).toBe(2);
  expect((await scroll(page)).top - before.top).toBe(before.height);
});

test('the place in a book set vertically survives a reload', async ({ page }) => {
  await start(page);
  await readBook(page, verticalBook('縦の頁'));
  for (let k = 2; k <= 4; k++) {
    await page.keyboard.press('ArrowLeft');
    await expect.poll(async () => (await place(page)).p).toBe(k);
  }
  const at = await place(page);
  const top = (await scroll(page)).top;
  const shown = await visibleText(page);
  // a reload in the middle of a book comes back to it
  await reload(page);
  await expect(indicator(page)).toContainText('in chapter');
  await expect.poll(async () => (await place(page)).p).toBe(at.p);
  expect((await place(page)).t).toBe(at.t);
  expect((await scroll(page)).top).toBe(top);
  expect(await visibleText(page)).toBe(shown);
});

test.describe('on a touch screen', () => {
  test.use({ hasTouch: true });

  test('a drag in a book set vertically does not follow the finger; a swipe to the right turns on', async ({ page }) => {
    await start(page);
    await readBook(page, verticalBook('縦スワイプ'));
    const box = await bookPage(page).boundingBox();
    const y = box.y + box.height / 2;
    const mid = box.x + box.width / 2;
    const swipe = (x0, x1, id) => bookPage(page).evaluate(async (el, [x0, x1, y, id]) => {
      const ev = (type, x) => el.dispatchEvent(new PointerEvent(type, {
        bubbles: true, pointerId: id, pointerType: 'touch', isPrimary: true, clientX: x, clientY: y,
      }));
      const wait = (t) => new Promise((r) => setTimeout(r, t));
      const start = [el.scrollLeft, el.scrollTop];
      const held = [];
      ev('pointerdown', x0);
      for (let i = 1; i <= 4; i++) { await wait(16); ev('pointermove', x0 + ((x1 - x0) * i) / 4); held.push([el.scrollLeft, el.scrollTop]); }
      await wait(16);
      ev('pointerup', x1);
      await wait(50);
      return held.every(([left, top]) => left === start[0] && top === start[1]);
    }, [x0, x1, y, id]);
    // held still while dragged to the right, then on to the next page
    expect(await swipe(mid - 60, mid + 60, 21)).toBe(true);
    await expect.poll(async () => (await place(page)).p).toBe(2);
    // a swipe to the left: back
    await swipe(mid + 60, mid - 60, 22);
    await expect.poll(async () => (await place(page)).p).toBe(1);
  });
});

// quire#391: digits lie on their side in vertical text (the default
// text-orientation: mixed turns Latin and digits). JLREQ sets a short
// number upright in one cell (tate-chu-yoko) and a longer number or a
// Latin word turned; `text-combine-upright: digits` is supported by no
// browser, so each run of one or two digits is wrapped in a text part (an
// element of the class tcy and the attribute data-part, which bridge counts
// as part of its content node's text) and set `text-combine-upright: all`.

test('a run of one or two digits in vertical text is set upright in one cell; a longer number, a word and a character reference are not', async ({ page }) => {
  await start(page);
  await readBook(page, {
    title: '縦書きの数', author: 'Vertical Tests', language: 'ja', rtl: true,
    rawChapters: [{ body: '<h1>第1章</h1><p>令和5年12月 2024年 A4判 &#49;&#50;&#51; 3.5</p>' }],
  });
  const style = await bookPage(page).locator('.tcy').first().evaluate(e => getComputedStyle(e).textCombineUpright);
  expect(style).toBe('all');
  // the runs wrapped: 1 of the heading; 5 and 12; and 3 and 5 of "3.5"
  const wrapped = await bookPage(page).locator('.tcy').allTextContents();
  expect(wrapped).toEqual(['1', '5', '12', '3', '5']);
  // a part is a part of its content node, which holds the whole text
  const heading = await bookPage(page).locator('h1').evaluate(e => {
    const node = e.querySelector('[id^=c]');
    return { id: node.id, text: node.textContent, parts: [...node.children].map(c => [c.dataset.part, c.className, c.textContent]) };
  });
  expect(heading.text).toBe('第1章');
  expect(heading.parts).toEqual([['1', '', '第'], ['1', 'tcy', '1'], ['1', '', '章']]);
  // the parts take no content node number of their own: after the heading's
  // text comes the paragraph (one number) and its text (the next)
  const next = await bookPage(page).locator('p').first().evaluate(e => e.querySelector('[id^=c]').id);
  expect(Number(next.slice(1))).toBe(Number(heading.id.slice(1)) + 2);
  // upright: the run stands in a cell one em tall (its width: the digits side
  // by side), where a digit on its side is about half an em tall, and a
  // run of three digits is not combined
  const cell = await bookPage(page).locator('h1').evaluate(e => {
    const run = e.querySelector('.tcy');
    const range = document.createRange();
    range.selectNodeContents(run);
    return { run: range.getBoundingClientRect().height, em: parseFloat(getComputedStyle(e).fontSize) };
  });
  expect(cell.run).toBeGreaterThan(cell.em * 0.9);
  expect(cell.run).toBeLessThan(cell.em * 1.1);
  // the text is as it was: a copy of the paragraph, character references decoded
  expect(await bookPage(page).locator('p').first().evaluate(e => e.textContent)).toBe('令和5年12月 2024年 A4判 123 3.5');
});

test('a mark over the text of a vertical heading with digits in it covers the text', async ({ page }) => {
  await start(page);
  await readBook(page, verticalBook('縦書き検索'));
  await page.keyboard.press('/');
  const panel = dialog(page, 'Search in book');
  await expect(panel).toBeVisible();
  await panel.getByRole('searchbox', { name: 'Search in book' }).fill('第1章');
  await expect(panel.getByRole('status')).toHaveText('1 result');
  await panel.getByRole('region', { name: 'Results' }).getByRole('button').first().click();
  // the match crosses the heading's three parts and is one range of text
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: '第1章' });
});

test('a selection over the digits of a vertical heading is kept with the whole text\'s offsets', async ({ page }) => {
  await start(page);
  await readBook(page, verticalBook('縦書き選択'));
  // select "1章" from the heading's second part to the end of its third
  await bookPage(page).locator('h1').evaluate(e => {
    const [, run, tail] = [...e.querySelectorAll('[data-part]')];
    const range = document.createRange();
    range.setStart(run.firstChild, 0);
    range.setEnd(tail.firstChild, 1);
    const selection = getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  });
  await expect(page.getByRole('toolbar', { name: 'Selection' })).toBeVisible();
  await selectionButton(page, 'Highlight').click();
  // the highlight is painted over exactly "1章", across two parts
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: '1章' });
});
