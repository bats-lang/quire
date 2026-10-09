// Page breaks that hold text or sit inside words (#421): KOReader lost the
// words of a page-break span (shkspr.mobi); here the words stay in the
// page, selectable, searchable and read aloud, the footer still names the
// print page, and what follows a break keeps its content node numbers.
// The books are in pagebreak-books.js.

import { test, expect } from './fixtures.js';
import {
  start, readBook, bookPage, visibleText, marks, dialog, selectionButton, control, showChrome,
} from './helpers.js';
import { pagebreakBooks } from './pagebreak-books.js';

const footerPage = page => page.getByText(/^ · page \d+ in print$/);
const searchPanel = page => dialog(page, 'Search in book');
const searchBox = page => searchPanel(page).getByRole('searchbox', { name: 'Search in book' });
const searchSummary = page => searchPanel(page).getByRole('status');
const searchResults = page => searchPanel(page).getByRole('region', { name: 'Results' }).getByRole('button');

async function search(page, text, count) {
  await page.keyboard.press('/');
  await expect(searchPanel(page)).toBeVisible();
  await searchBox(page).fill(text);
  await expect(searchSummary(page)).toHaveText(count === 1 ? '1 result' : `${count} results`);
}

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

test('text inside a page-break span is shown, selectable and searchable, and the footer names the print page', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, pagebreakBooks.textInside.opts);
  const text = await visibleText(page);
  expect(text).toContain('‘But of course!’ said the first.');
  expect(text).toContain('Wait what? asked the second.');
  // the words are the page's: selectable
  await selectWord(page, 'But');
  await expect(selectionButton(page, 'Highlight')).toBeVisible();
  // searchable: the break's own words, and those after it (a hit is
  // inside one text, so a phrase across the break's end is not found:
  // quire#437)
  await search(page, 'But', 1);
  await searchResults(page).first().click();
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: 'But' });
  await page.getByRole('button', { name: 'Close search' }).click();
  await search(page, 'course', 1);
  await searchResults(page).first().click();
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: 'course' });
  await page.getByRole('button', { name: 'Close search' }).click();
  await search(page, 'Wait', 1);
  await searchResults(page).first().click();
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: 'Wait' });
  // the footer names the print page from the title, with the text there
  await page.keyboard.press('t');
  await expect(footerPage(page)).toHaveText(' · page 10 in print');
  expect(errors).toEqual([]);
});

// Decided (issue 421). The EPUB Accessibility techniques (DAISY's
// knowledge base) have a page number either as an empty element named by
// aria-label (or title), or as the element's visible text, "more easily
// accessible to both sighted users and users using assistive
// technologies", and note that mainstream reading systems give no way to
// turn the visible form off; KOReader ignores any text inside a page break
// (the bug above), and the hiding rule for ADE and Apple Books is a
// publisher's own CSS. The book's own CSS is dropped here, so Quire shows
// the text as the book has it and never hides words a book put in the
// page. The footer names a print page from the break's title, else its
// aria-label (which the techniques require even when the number is
// visible); a break with neither is shown, and names no page.
test('a page break whose text is the page number is shown as the book has it, and names the print page', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, pagebreakBooks.numberText.opts);
  expect(await visibleText(page)).toContain('Page ten ends here.');
  expect(await visibleText(page)).toContain('10 And page eleven begins.');
  await page.keyboard.press('t');
  await expect(footerPage(page)).toHaveText(' · page 10 in print');
  // the second has no title or label: shown, and the footer keeps the page before
  expect(await visibleText(page)).toContain('20 After the number twenty.');
  expect(errors).toEqual([]);
});

test('a block-level page break neither hides nor duplicates the text round it, and a break inside a word or an inline element leaves it whole', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, pagebreakBooks.structure.opts);
  const text = await visibleText(page);
  expect(text.match(/Before the block break\./g)).toHaveLength(1);
  expect(text.match(/After the block break\./g)).toHaveLength(1);
  expect(text).toContain('An unbelievable word.');
  expect(text).toContain('An emphasis inside.');
  // each part of the split word is found where it is
  await search(page, 'believable', 1);
  await searchResults(page).first().click();
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: 'believable' });
  expect(errors).toEqual([]);
});

test('a search hit and a highlight after the breaks keep their place in the text', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, pagebreakBooks.structure.opts);
  await page.keyboard.press('/');
  await searchBox(page).fill('needle after every break');
  await expect(searchSummary(page)).toHaveText('1 result');
  await searchResults(page).first().click();
  await expect.poll(() => marks(page)).toEqual({ size: 1, text: 'needle after every break' });
  await page.getByRole('button', { name: 'Close search' }).click();
  // a highlight there is marked on the same words after the page is laid out again
  await selectWord(page, 'needle');
  await selectionButton(page, 'Highlight').click();
  await expect.poll(async () => (await marks(page)).text).toContain('needle');
  expect(errors).toEqual([]);
});

// Read aloud's script is the text of each block: the words of a break's
// span are in it, the page number (a break whose text is the number) is
// said where the book has it
async function fakeSpeech(page) {
  await page.addInitScript(() => {
    window.spoken = [];
    window.SpeechSynthesisUtterance = class { constructor(text) { this.text = text; } };
    const voices = [{ name: 'Reader', lang: 'en-US', voiceURI: 'reader-en', default: true }];
    const synth = {
      current: null,
      getVoices: () => voices,
      speak(u) { window.spoken.push(u.text); this.current = u; },
      cancel() { const u = this.current; this.current = null; if (u && u.onerror) u.onerror({ error: 'interrupted' }); },
      addEventListener() {},
    };
    Object.defineProperty(window, 'speechSynthesis', { value: synth });
    window.sentenceSpoken = () => { const u = synth.current; synth.current = null; if (u && u.onend) u.onend({}); };
  });
}

test('read aloud says the words inside a page-break span, with those round it', async ({ page }) => {
  await fakeSpeech(page);
  const errors = await start(page);
  await readBook(page, pagebreakBooks.textInside.opts);
  await showChrome(page);
  await control(page, 'Read aloud').click();
  for (let k = 0; k < 5; k++) {
    await expect.poll(() => page.evaluate(() => window.spoken.length)).toBeGreaterThan(k);
    await page.evaluate(() => window.sentenceSpoken());
  }
  const said = await page.evaluate(() => window.spoken);
  expect(said.join(' ')).toContain('\u2018But of course!\u2019 said the first.');
  expect(said.join(' ')).toContain('Wait what? asked the second.');
  expect(errors).toEqual([]);
});
