// Character encodings (#436). EPUB 3 requires UTF-8 or UTF-16, but books
// have a byte order mark, are in UTF-16, or (EPUB 2 files) in ISO-8859-1,
// windows-1252 or windows-1255, with a wrong declaration or none. Decided
// (src/text_encoding.bats): a document is read as its byte order mark or
// its XML declaration says, as Thorium, Calibre and Apple Books do; a
// document that says a single-byte encoding Quire has a table for is
// decoded by it; a document that is not UTF-8 and says nothing else, or an
// encoding Quire has no table for, is refused with the words "Chapter N of
// this book could not be read", never shown as mojibake. The books are in
// encoding-books.js, checked by epubcheck.spec.js.

import { test, expect } from './fixtures.js';
import {
  start, readBook, importFiles, epubFile, openBook, card, cards, titles, bookPage, place, showChrome, control, dialog,
  clickControl, bookMenu, menuItem, chooseInSortMenu, reload, toLibrary, visibleText, expectBannerSaysWhatToDo,
} from './helpers.js';
import { encodingBooks, names } from './encoding-books.js';

const alert = page => page.getByRole('alert');
const searchPanel = page => dialog(page, 'Search in book');
const summary = page => searchPanel(page).getByRole('status');

/** The text of the page, whole (not only what is on the screen) */
const pageText = page => bookPage(page).evaluate(el => el.textContent);

/** Searches the book for text: how many results it says */
async function searched(page, text) {
  await page.keyboard.press('/');
  await expect(searchPanel(page)).toBeVisible();
  await page.keyboard.type(text);
  await expect(summary(page)).toHaveText(/^(\d+ results?|No results.*)$/);
  const said = await summary(page).textContent();
  await page.keyboard.press('Escape');
  await expect(searchPanel(page)).toBeHidden();
  return said;
}

async function fakeSpeech(page) {
  await page.addInitScript(() => {
    window.spoken = [];
    window.SpeechSynthesisUtterance = class { constructor(text) { this.text = text; } };
    const voices = [{ name: 'Reader', lang: 'en-US', voiceURI: 'reader-en', default: true }];
    const synth = {
      current: null,
      getVoices: () => voices,
      speak(u) { window.spoken.push({ text: u.text, lang: u.lang }); this.current = u; },
      cancel() { const u = this.current; this.current = null; if (u && u.onerror) u.onerror({ error: 'interrupted' }); },
      addEventListener() {},
    };
    Object.defineProperty(window, 'speechSynthesis', { value: synth });
    window.sentenceSpoken = () => { const u = synth.current; synth.current = null; if (u && u.onend) u.onend({}); };
  });
}
const spoken = page => page.evaluate(() => window.spoken);

test('a book with a UTF-8 byte order mark on its chapter, package and navigation document is read, with no stray U+FEFF', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, encodingBooks.bom.opts);
  expect(await pageText(page)).toContain('Quillon is the first word');
  expect(await pageText(page)).not.toContain('﻿');
  expect(await pageText(page)).not.toContain('�');
  // the first word is searchable
  expect(await searched(page, 'Quillon')).toBe('1 result');
  // the navigation document: its entries are the contents
  await showChrome(page);
  await control(page, 'Contents').click();
  await expect(dialog(page, 'Contents')).toContainText('Chapter 1');
  await expect(dialog(page, 'Contents')).toContainText('Chapter 2');
  await page.keyboard.press('Escape');
  await toLibrary(page);
  await expect(card(page, 'Byte Order Mark')).toContainText('Encoding Tests');
  expect(await card(page, 'Byte Order Mark').innerText()).not.toContain('﻿');
  expect(errors).toEqual([]);
});

for (const order of ['utf16le', 'utf16be']) {
  test(`a chapter in UTF-16 (${order === 'utf16le' ? 'little' : 'big'} endian, with its byte order mark) is read as text, searched and read aloud`, async ({ page }) => {
    await fakeSpeech(page);
    const errors = await start(page);
    await readBook(page, encodingBooks[order].opts);
    expect(await pageText(page)).toContain('Quillon is the first word of this chapter, and the rest is as plain as can be.');
    expect(await pageText(page)).not.toMatch(/[﻿�\u0000]/);
    expect(await searched(page, 'Quillon')).toBe('1 result');
    expect(await searched(page, 'plain as can be')).toBe('1 result');
    // read aloud: the chapter's sentences
    await showChrome(page);
    await control(page, 'Read aloud').click();
    await expect.poll(async () => (await spoken(page)).length).toBe(1);
    expect((await spoken(page))[0].text).toBe('Part One');
    await page.evaluate(() => window.sentenceSpoken());
    await expect.poll(async () => (await spoken(page)).length).toBe(2);
    expect((await spoken(page))[1].text).toBe('Quillon is the first word of this chapter, and the rest is as plain as can be.');
    // the second chapter, in UTF-8, is read too
    await control(page, 'Read aloud').click();
    await page.keyboard.press('ArrowRight');
    await expect.poll(async () => (await place(page)).ch).toBe(2);
    expect(await pageText(page)).toContain('Zanzibar second chapter');
    expect(errors).toEqual([]);
  });
}

test('a chapter declared ISO-8859-1 (an EPUB 2 file) is decoded by its declaration, no mojibake', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, encodingBooks.latin1.opts);
  expect(await pageText(page)).toContain('Quillon café Zoë niño, Ångström and "quoted" text.');
  expect(await pageText(page)).not.toMatch(/\uFFFD|Ã/);
  expect(await searched(page, 'Ångström')).toBe('1 result');
  expect(errors).toEqual([]);
});

test('a chapter declared windows-1252 is decoded by it: curly quotes, a dash and the euro sign', async ({ page }) => {
  await start(page);
  await readBook(page, encodingBooks.windows1252.opts);
  expect(await pageText(page)).toContain('Quillon costs 5€ – “quoted” – and ‘single’.');
  expect(await pageText(page)).not.toContain('�');
});

test('a chapter declared windows-1255 holds Hebrew in single bytes, decoded by the declaration', async ({ page }) => {
  await start(page);
  await readBook(page, encodingBooks.windows1255.opts);
  expect(await pageText(page)).toContain('Quillon שלום עולם, מה שלומך היום?');
  expect(await pageText(page)).not.toContain('�');
  expect(await searched(page, 'שלום')).toBe('1 result');
});

test('a chapter declared ISO-8859-1 whose bytes are UTF-8 is read as UTF-8, not as mojibake', async ({ page }) => {
  await start(page);
  await readBook(page, encodingBooks.latin1DeclaredUtf8.opts);
  expect(await pageText(page)).toContain('Quillon café Zoë niño, Ångström');
  expect(await pageText(page)).not.toMatch(/Ã/);
});

for (const [name, why] of [
  ['undeclaredLatin1', 'with no declaration and no byte order mark, whose bytes are not UTF-8'],
  ['utf8DeclaredLatin1', 'declared UTF-8 whose bytes are not'],
  ['shiftJis', 'in an encoding Quire has no table for (Shift_JIS)'],
]) {
  test(`a chapter ${why} is refused with words, not shown as mojibake`, async ({ page }, testInfo) => {
    await start(page);
    await readBook(page, encodingBooks[name].opts);
    expect(await pageText(page)).toContain('Alpha, one short page.');
    await expect(alert(page)).toBeHidden();
    // turned to, it is refused: the reader stays on the page it was on, and the banner says what to do
    await page.keyboard.press('ArrowRight');
    await expect(alert(page)).toBeVisible();
    await expect(alert(page)).toContainText('Chapter 2 of this book could not be read');
    await expectBannerSaysWhatToDo(page, testInfo);
    expect(await place(page)).toMatchObject({ ch: 1 });
    expect(await pageText(page)).toContain('Alpha, one short page.');
    expect(await pageText(page)).not.toMatch(/�|Ã/);
  });
}

test('character references over the whole range are decoded: numeric, one past the BMP, and the invisible ones', async ({ page }) => {
  await start(page);
  await readBook(page, encodingBooks.references.opts);
  const text = await pageText(page);
  expect(text).toContain('Quillon \u{1F600} ב ‏|‍| é אב & < > " \' €  end');
  expect(text).not.toMatch(/&#/);
  // searched as the characters are, by the letters
  expect(await searched(page, '\u{1F600}')).toBe('1 result');
});

test('HTML\'s named references in XHTML are decoded too: nbsp, rlm, zwj, eacute, hellip, mdash', async ({ page }) => {
  await start(page);
  await readBook(page, encodingBooks.namedReferences.opts);
  expect(await pageText(page)).toContain('Quillon  |‏|‍| é … — © end');
});

test('a character of four bytes cut by the 64 KiB pieces a text is passed on in is shown whole', async ({ page }) => {
  await start(page);
  await readBook(page, encodingBooks.emojiCut.opts);
  const text = await pageText(page);
  expect(text).not.toContain('�');
  for (const [word, at] of [['ALPHA', 65533], ['BRAVO', 65534], ['CHARLIE', 65535]]) {
    const expected = `${word}-${'a'.repeat(at - word.length - 1)}\u{1F600}END-${word}`;
    expect(text.includes(expected), `${word}'s paragraph, whole`).toBe(true);
  }
});

// Titles and authors: the OPF's references are decoded, the letters show
// right, and the library sorts by the letters (Łukasz is under L)
test('a title and an author with references and non-ASCII letters show right on the card and in Book info', async ({ page }) => {
  const errors = await start(page);
  const files = names.map((_, k) => epubFile(encodingBooks[`name ${k}`].opts));
  await importFiles(page, files, names.length);
  for (const [, shown, , author] of names) {
    await expect(card(page, shown)).toContainText(author);
    expect(await card(page, shown).innerText()).not.toMatch(/&#|&amp;|�/);
  }
  // Book info says the same
  await bookMenu(page, 'Łukasz Book');
  await menuItem(page, 'Book info').click();
  await expect(dialog(page, 'Book info')).toContainText('Łukasz Book');
  await expect(dialog(page, 'Book info')).toContainText('Łukasz Author');
  await page.keyboard.press('Escape');
  expect(errors).toEqual([]);
});

test('the library sorts titles and authors by their letters: Łukasz under L, Zoë with Zoe, scripts after Latin', async ({ page }) => {
  await start(page);
  await importFiles(page, names.map((_, k) => epubFile(encodingBooks[`name ${k}`].opts)), names.length);
  await chooseInSortMenu(page, 'Title');
  await expect.poll(() => titles(page)).toEqual([
    'Lambda Book', 'Łukasz Book', 'Mu Book', 'Zeta Book', 'Zoë Book', 'Zoë Direct', 'שלום עולם', '日本語の本',
  ]);
  // by author: Anna, Ben, Cora, Łukasz Author, Łukasz Direct, Zoë Author, then the scripts
  await chooseInSortMenu(page, 'Author');
  await expect.poll(() => titles(page)).toEqual([
    'Zeta Book', 'Lambda Book', 'Mu Book', 'Łukasz Book', 'Zoë Direct', 'Zoë Book', 'שלום עולם', '日本語の本',
  ]);
});
