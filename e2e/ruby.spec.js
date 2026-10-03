// Ruby: a word's reading (furigana) shown over it, kept out of search,
// and hidden or shown from the settings, which offer it only for a book
// that has some.

import { test, expect } from './fixtures.js';
import {
  start, readBook, importFiles, epubFile, openBook, toLibrary, reload, bookPage, dialog, openSettings,
  selectionButton, marks, chapters, chapterBody, cards,
} from './helpers.js';

const filler = 'lorem ipsum dolor sit amet '.repeat(12);
const rubyChapter = {
  body: '<h1>Part 1</h1>'
    + `<p>Before the city <ruby>東京<rp>(</rp><rt>とうきょう</rt><rp>)</rp></ruby> the river bends. ${filler}</p>`
    + `<p>Afterward the Zebra crossing. ${filler}</p>`
    + Array.from({ length: 10 }, (_, k) => `<p>Para 1.${k} ${filler}</p>`).join(''),
};
const rubyBook = { title: 'Furigana', author: 'Ruby Tests', rawChapters: [rubyChapter, { body: chapterBody(2) }] };
const plainBook = { title: 'Plain Text', author: 'Ruby Tests', rawChapters: chapters(2) };

const sheet = page => dialog(page, 'Typography and theme');
const rubyGroup = page => sheet(page).getByRole('group', { name: 'Ruby annotations' });
const display = (page, tag) => bookPage(page).locator(tag).first().evaluate(e => getComputedStyle(e).display);

const searchPanel = page => dialog(page, 'Search in book');
const searchBox = page => searchPanel(page).getByRole('searchbox', { name: 'Search in book' });
const searchSummary = page => searchPanel(page).getByRole('status');
const searchResults = page => searchPanel(page).getByRole('region', { name: 'Results' }).getByRole('button');

/** Selects the word in the first text of the page that holds it */
async function selectWord(page, word) {
  await bookPage(page).evaluate((doc, word) => {
    const walker = document.createTreeWalker(doc, NodeFilter.SHOW_TEXT);
    for (let t = walker.nextNode(); t; t = walker.nextNode()) {
      const at = t.data.indexOf(word);
      if (at < 0) continue;
      const r = document.createRange();
      r.setStart(t, at);
      r.setEnd(t, at + word.length);
      const s = getSelection();
      s.removeAllRanges();
      s.addRange(r);
      return;
    }
    throw new Error(`no text holds ${word}`);
  }, word);
}

test('a ruby is shown as one: its reading over its base, its parentheses not shown', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, rubyBook);
  await expect(bookPage(page).locator('ruby')).toHaveCount(1);
  await expect(bookPage(page).locator('rt')).toBeVisible();
  await expect(bookPage(page).locator('rt')).toHaveText('とうきょう');
  expect(await display(page, 'rt')).not.toBe('none');
  await expect(bookPage(page).locator('rp')).toHaveCount(2);
  expect(await bookPage(page).locator('rp').evaluateAll(all => all.map(e => getComputedStyle(e).display)))
    .toEqual(['none', 'none']);
  // the reading sits above its base, over it
  const base = await bookPage(page).locator('ruby').evaluate(e => {
    const r = e.firstElementChild.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2, left: r.left, right: r.right };
  });
  const reading = await bookPage(page).locator('rt').evaluate(e => {
    const r = e.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2, left: r.left, right: r.right };
  });
  expect(reading.y).toBeLessThan(base.y);
  expect(reading.right).toBeGreaterThan(base.left);
  expect(reading.left).toBeLessThan(base.right);
  expect(errors).toEqual([]);
});

test('the Ruby row is offered only for a book with ruby; Hide and Show are kept', async ({ page }) => {
  const errors = await start(page);
  await importFiles(page, [epubFile(rubyBook), epubFile(plainBook)], 2);
  await openBook(page, 'Plain Text');
  await openSettings(page);
  await expect(rubyGroup(page)).toBeHidden();
  await page.keyboard.press('Escape');
  await toLibrary(page);
  await openBook(page, 'Furigana');
  await openSettings(page);
  await expect(rubyGroup(page)).toBeVisible();
  await expect(rubyGroup(page).getByRole('button', { name: 'Show' })).toHaveAttribute('aria-pressed', 'true');
  await rubyGroup(page).getByRole('button', { name: 'Hide' }).click();
  await expect.poll(() => display(page, 'rt')).toBe('none');
  await expect(rubyGroup(page).getByRole('button', { name: 'Hide' })).toHaveAttribute('aria-pressed', 'true');
  await rubyGroup(page).getByRole('button', { name: 'Show' }).click();
  await expect.poll(() => display(page, 'rt')).not.toBe('none');
  await rubyGroup(page).getByRole('button', { name: 'Hide' }).click();
  await expect.poll(() => display(page, 'rt')).toBe('none');
  await page.keyboard.press('Escape');
  // a reload comes back to the book, with the annotations still hidden
  await reload(page);
  await expect(bookPage(page)).toBeVisible();
  await expect(bookPage(page).locator('rt')).toHaveCount(1);
  await expect.poll(() => display(page, 'rt')).toBe('none');
  await openSettings(page);
  await expect(rubyGroup(page).getByRole('button', { name: 'Hide' })).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('Escape');
  // the row goes again for the next book, which has none
  await toLibrary(page);
  await expect(cards(page)).toHaveCount(2);
  await openBook(page, 'Plain Text');
  await openSettings(page);
  await expect(rubyGroup(page)).toBeHidden();
  expect(errors).toEqual([]);
});

test('search finds a ruby\'s base, not its reading, and what follows it where it is', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, rubyBook);
  await page.keyboard.press('/');
  await expect(searchPanel(page)).toBeVisible();
  await searchBox(page).fill('とうきょう');
  await expect(searchSummary(page)).toHaveText('No results');
  await searchBox(page).fill('東京');
  await expect(searchSummary(page)).toHaveText('1 result');
  await expect(searchResults(page)).toHaveCount(1);
  await searchResults(page).first().click();
  await expect(searchPanel(page)).toBeHidden();
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: '東京' });
  // a match after the ruby is marked on its own text: the search counts
  // the ruby's nodes as the page made them
  await page.getByRole('button', { name: 'Close search' }).click();
  await page.keyboard.press('/');
  await searchBox(page).fill('river bends');
  await expect(searchSummary(page)).toHaveText('1 result');
  await searchResults(page).first().click();
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: 'river bends' });
  await page.getByRole('button', { name: 'Close search' }).click();
  await page.keyboard.press('/');
  await searchBox(page).fill('zebra');
  await expect(searchSummary(page)).toHaveText('1 result');
  await searchResults(page).first().click();
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: 'Zebra' });
  expect(errors).toEqual([]);
});

test('a highlight after a ruby lands on its own text, and is kept there', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, rubyBook);
  await selectWord(page, 'river');
  await selectionButton(page, 'Highlight').click();
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: 'river' });
  await selectWord(page, 'Zebra');
  await selectionButton(page, 'Highlight').click();
  await expect.poll(async () => (await marks(page)).size).toBe(2);
  await toLibrary(page);
  await reload(page);
  await openBook(page, 'Furigana');
  await expect.poll(() => page.evaluate(() => {
    const texts = [];
    for (const [, h] of CSS.highlights) for (const r of h) texts.push(r.toString());
    return texts.sort();
  })).toEqual(['Zebra', 'river']);
  expect(errors).toEqual([]);
});
