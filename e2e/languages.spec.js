// Missing, odd and contradicted languages (#436). Decided (research: Thorium,
// Calibre and Apple Books take the language from the package and the
// documents, and none guesses it from the text; BCP 47 and ICU write
// "eng" as "en"):
// - Quire does not guess a book's language from its text. A book with no
//   dc:language is "und" (undetermined), its voice automatic and its Look
//   up in English; its direction is its package's (page-progression-direction,
//   or a right-to-left language), and the text itself is set by the Unicode
//   bidirectional algorithm, so Hebrew reads right to left in it. Japanese
//   text is vertical only when the language says Japanese (vertical-rl needs
//   it, as Readium decides).
// - A chapter's own xml:lang (its html or body) is the language of that
//   chapter: the page's lang (so its hyphenation), the voice and the Look up.
// - dc:language is read as BCP 47 (language.bats): any case, "_" or "-",
//   ISO 639-2 codes as their two-letter ones, the first of several; the
//   voice and the dictionary go by its primary subtag.
// - xml:lang on an element is kept on its content node, and a phrase in
//   another language is read aloud in it.
// The books are in language-books.js, checked by epubcheck.spec.js.

import { test, expect } from './fixtures.js';
import {
  start, readBook, bookPage, place, showChrome, control, selectText, expectBarFollows, toLibrary,
} from './helpers.js';
import { languageBooks, forms, hebrewBody } from './language-books.js';

const pageLang = page => bookPage(page).getAttribute('lang');
const lookUp = page => page.getByRole('toolbar', { name: 'Selection' }).getByRole('link', { name: 'Look up' });

async function fakeSpeech(page) {
  await page.addInitScript(() => {
    window.spoken = [];
    window.SpeechSynthesisUtterance = class { constructor(text) { this.text = text; } };
    const voices = [
      { name: 'Reader', lang: 'en-US', voiceURI: 'reader-en', default: true },
      { name: 'Lecteur', lang: 'fr-FR', voiceURI: 'lecteur-fr', default: false },
      { name: 'Narrator', lang: 'he-IL', voiceURI: 'narrator-he', default: false },
    ];
    const synth = {
      current: null,
      getVoices: () => voices,
      speak(u) { window.spoken.push({ text: u.text, lang: u.lang, voice: u.voice && u.voice.name }); this.current = u; },
      cancel() { const u = this.current; this.current = null; if (u && u.onerror) u.onerror({ error: 'interrupted' }); },
      addEventListener() {},
    };
    Object.defineProperty(window, 'speechSynthesis', { value: synth });
    window.sentenceSpoken = () => { const u = synth.current; synth.current = null; if (u && u.onend) u.onend({}); };
  });
}
const spoken = page => page.evaluate(() => window.spoken);

/** Reads aloud from the top of the page: the utterances said until n have been, each ended in turn */
async function readAloud(page, n) {
  await showChrome(page);
  await control(page, 'Read aloud').click();
  for (let k = 1; k <= n; k++) {
    await expect.poll(async () => (await spoken(page)).length).toBeGreaterThanOrEqual(k);
    if (k < n) await page.evaluate(() => window.sentenceSpoken());
  }
  return spoken(page);
}

test('Hebrew text in a book that names no language: und, read left to right by its package, the text itself right to left, spoken and looked up with nothing guessed', async ({ page }) => {
  await fakeSpeech(page);
  const errors = await start(page);
  await readBook(page, languageBooks.hebrewNoLanguage.opts);
  // the page is undetermined, not English and not Hebrew
  expect(await pageLang(page)).toBe('und');
  // its direction is the package's: left to right, the bar as for any such book
  expect(await bookPage(page).evaluate(e => getComputedStyle(e).direction)).toBe('ltr');
  await expectBarFollows(page, false);
  // the text itself runs right to left, by the Unicode algorithm: of two Hebrew words on a line, the first is on the right
  const order = await bookPage(page).evaluate(doc => {
    const p = doc.querySelectorAll('p')[1];
    const walker = document.createTreeWalker(p, NodeFilter.SHOW_TEXT);
    let node = walker.nextNode();
    while (node && !node.textContent.includes('עולם')) node = walker.nextNode();
    const rect = (from, to) => { const r = document.createRange(); r.setStart(node, from); r.setEnd(node, to); return r.getBoundingClientRect(); };
    const text = node.textContent;
    const first = text.indexOf('שלום');
    const second = text.indexOf('עולם');
    return { first: rect(first, first + 4), second: rect(second, second + 4) };
  });
  expect(order.first.right).toBeGreaterThan(order.second.right);
  // looked up in English, as a book with no language is (annotations.spec.js)
  await selectText(page, 0, 4);
  await expect(lookUp(page)).toHaveAttribute('href', /^https:\/\/en\.wiktionary\.org\//);
  // spoken with no language named: the voice is the automatic one
  const said = await readAloud(page, 1);
  expect(said[0].lang || '').toBe('');
  expect(said[0].voice).toBeUndefined();
  expect(errors).toEqual([]);
});

test('Japanese text in a book that names no language is not set vertically: the setting needs the language', async ({ page }) => {
  await start(page);
  await readBook(page, languageBooks.japaneseNoLanguage.opts);
  expect(await pageLang(page)).toBe('und');
  expect(await bookPage(page).evaluate(e => getComputedStyle(e).writingMode)).toBe('horizontal-tb');
  await toLibrary(page);
  // the same text with its language is vertical (vertical.spec.js)
  await readBook(page, languageBooks.japaneseWithLanguage.opts);
  expect(await pageLang(page)).toBe('ja');
  expect(await bookPage(page).evaluate(e => getComputedStyle(e).writingMode)).toBe('vertical-rl');
});

test('a chapter whose xml:lang says Hebrew in a book that says English: the chapter\'s wins for the page, the voice and the look up, and the next chapter is English again', async ({ page }) => {
  await fakeSpeech(page);
  const errors = await start(page);
  await readBook(page, languageBooks.chapterOverrides.opts);
  expect(await pageLang(page)).toBe('he');
  await selectText(page, 0, 4);
  await expect(lookUp(page)).toHaveAttribute('href', /^https:\/\/he\.wiktionary\.org\//);
  const said = await readAloud(page, 1);
  expect(said[0].lang).toBe('he');
  // the second chapter says nothing: the book's language
  await control(page, 'Read aloud').click();
  await page.keyboard.press('End');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).ch).toBe(2);
  expect(await pageLang(page)).toBe('en');
  await selectText(page, 0, 4);
  await expect(lookUp(page)).toHaveAttribute('href', /^https:\/\/en\.wiktionary\.org\//);
  expect(errors).toEqual([]);
});

for (const [name, written, tag] of forms) {
  test(`dc:language ${written} is read as ${tag}: the page, the voice and the dictionary go by it`, async ({ page }) => {
    await fakeSpeech(page);
    await start(page);
    await readBook(page, languageBooks[`form ${name}`].opts);
    expect(await pageLang(page)).toBe(tag);
    await selectText(page, 0, 4);
    await expect(lookUp(page)).toHaveAttribute('href', new RegExp(`^https://${tag.split('-')[0]}\\.wiktionary\\.org/`));
    // spoken in the tag, whose primary subtag the engine's voice is found by
    const said = await readAloud(page, 1);
    expect(said[0].lang).toBe(tag);
  });
}

test('two dc:language elements: the first is the book\'s', async ({ page }) => {
  await start(page);
  await readBook(page, languageBooks['two languages'].opts);
  expect(await pageLang(page)).toBe('fr');
  await selectText(page, 0, 4);
  await expect(lookUp(page)).toHaveAttribute('href', /^https:\/\/fr\.wiktionary\.org\//);
});

test('xml:lang on an inline span is kept on its content node, and the phrase is read aloud in its language', async ({ page }) => {
  await fakeSpeech(page);
  const errors = await start(page);
  await readBook(page, languageBooks.frenchSpan.opts);
  // kept: on the span and on the paragraph that says it, and not on the others
  const langs = await bookPage(page).evaluate(doc => [...doc.querySelectorAll('[lang]')].map(e => [e.tagName.toLowerCase(), e.getAttribute('lang'), e.textContent.slice(0, 12)]));
  expect(langs).toEqual([['span', 'fr', "c'est la vie"], ['p', 'fr', 'Ceci est un ']]);
  // read aloud: the English before the phrase, the phrase in French, the English after it, the French paragraph, and English again
  const said = await readAloud(page, 6);
  const heard = said.map(s => [s.text, s.lang]);
  expect(heard.slice(0, 7)).toEqual([
    ['Chapter One', 'en'],
    ['She said', 'en'],
    ["c'est la vie", 'fr'],
    ['and left the room quietly.', 'en'],
    ['Ceci est un paragraphe tout entier en français.', 'fr'],
    ['Il y a deux phrases.', 'fr'],
  ].slice(0, heard.length));
  expect(errors).toEqual([]);
});
