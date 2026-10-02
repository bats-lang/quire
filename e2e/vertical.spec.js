// Vertical writing: a Japanese (Chinese, Korean) book read right to left
// is set vertically, as Readium sets it from its OPF (the book's own CSS
// is not used). Its columns follow the inline axis, down the page, so
// its pages go down: a turn scrolls one page height.

import { test, expect } from '@playwright/test';
import {
  start, importFiles, epubFile, openBook, readBook, toLibrary, reload, bookPage, dialog, openSettings,
  place, indicator, chapters, japaneseChapters,
} from './helpers.js';

const verticalBook = (title) => ({ title, author: 'Vertical Tests', language: 'ja', rtl: true, rawChapters: japaneseChapters(2, 40) });

const sheet = page => dialog(page, 'Typography and theme');

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

test('a Japanese book read right to left is set vertically, its pages going down', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, verticalBook('縦書き'));
  const style = await bookPage(page).evaluate(e => ({ mode: getComputedStyle(e).writingMode, direction: getComputedStyle(e).direction }));
  expect(style).toEqual({ mode: 'vertical-rl', direction: 'ltr' });
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
  await openSettings(page);
  await expect(sheet(page).getByRole('group', { name: 'Layout' })).toBeHidden();
  await expect(sheet(page).getByRole('group', { name: 'Columns' })).toBeHidden();
  await expect(sheet(page).getByRole('slider', { name: 'Margins' })).toBeHidden();
  await expect(sheet(page).getByRole('group', { name: 'Alignment' })).toBeHidden();
  await expect(sheet(page).getByRole('group', { name: 'Hyphenation' })).toBeHidden();
  await page.keyboard.press('Escape');
  await toLibrary(page);
  await openBook(page, 'Across');
  await openSettings(page);
  await expect(sheet(page).getByRole('group', { name: 'Layout' })).toBeVisible();
  await expect(sheet(page).getByRole('group', { name: 'Columns' })).toBeVisible();
  await expect(sheet(page).getByRole('slider', { name: 'Margins' })).toBeVisible();
  await expect(sheet(page).getByRole('group', { name: 'Alignment' })).toBeVisible();
  await expect(sheet(page).getByRole('group', { name: 'Hyphenation' })).toBeVisible();
  // and the horizontal book is not set vertically
  expect(await bookPage(page).evaluate(e => getComputedStyle(e).writingMode)).toBe('horizontal-tb');
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
  await openSettings(page);
  await expect(sheet(page).getByRole('slider', { name: 'Paragraph spacing' })).toBeVisible();
});

test('a book set vertically is paged even when the layout is scrolled', async ({ page }) => {
  await start(page);
  await importFiles(page, [epubFile(verticalBook('段組')), epubFile({ title: 'Scrolled', author: 'Vertical Tests', rawChapters: chapters(1) })], 2);
  await openBook(page, 'Scrolled');
  await openSettings(page);
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
