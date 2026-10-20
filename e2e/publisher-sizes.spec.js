// The reader's text size is the reading size in every book, and the
// publisher's other sizes keep their proportion to the body text (#431).
// The books are in size-books.js: A sets its
// text in a rem chain (html 62.5%, 1.6rem), B in points, a class and an inline
// style; the others put the size on body, on a div, by html and rem, by
// calc() (not read), in a part title page of headings, in 1px and 400% rules,
// beside every other property a stylesheet can set, and in a linked sheet.
//
// What is checked is the page's computed font-size, as settings.spec.js
// reads it. The measure that decides the body text of a book (the size most
// of its characters are set in, src/css_cascade.bats) is tested on bytes by
// tests/css-size; this is what it does to the page.

import { test, expect } from './fixtures.js';
import { readFileSync } from 'node:fs';
import {
  start, readBook, openBook, toLibrary, bookPage, dialog, reload, rawFile, showChrome, control,
  readingSettings, openReadingSettings, librarySettings, exportedBackup, restoreInput, settingsButton,
  onPage,
} from './helpers.js';
import { sizeBooks } from './size-books.js';

const respectSwitch = page => readingSettings(page).getByRole('button', { name: 'Respect the publisher\'s sizes', exact: true });

/** The Size setting, from the reading settings' Look tab */
async function setSize(page, size) {
  await openReadingSettings(page, 'Look');
  await readingSettings(page).getByRole('slider', { name: 'Size' }).fill(String(size));
  await page.keyboard.press('Escape');
  await expect(readingSettings(page)).toBeHidden();
}

/** The computed font-size of the first element on the page that matches
    selector (and holds text, when given) */
const fontSize = (page, selector, text) =>
  bookPage(page).locator(selector, text ? { hasText: text } : {}).first().evaluate(e => parseFloat(getComputedStyle(e).fontSize));

const BODY = 'Body text of the first paragraph';
const body = (page) => fontSize(page, 'p', BODY);
const h1 = page => fontSize(page, 'h1', 'A Title');
const h2 = page => fontSize(page, 'h2', 'A Subtitle');
const small = page => fontSize(page, 'small');
const lead = page => fontSize(page, 'p', 'The opening paragraph');
const caption = page => fontSize(page, 'p', 'A caption');

/** The reader's size, then the chapter named label, from the contents */
async function chapterNamed(page, label) {
  await showChrome(page);
  await control(page, 'Contents').click();
  await dialog(page, 'Contents').getByRole('tabpanel', { name: 'Contents' }).getByRole('button', { name: label, exact: true }).click();
  await expect(dialog(page, 'Contents')).toBeHidden();
}

test('at the same Size, the body text of two books set in different units is the setting, at the smallest, the middle and the largest', async ({ page }) => {
  const errors = await start(page);
  for (const [name, book] of [['relative', sizeBooks.relative], ['absolute', sizeBooks.absolute], ['legacy', sizeBooks.legacy]]) {
    await readBook(page, book.opts);
    for (const size of [12, 20, 32]) {
      await setSize(page, size);
      await expect.poll(() => body(page), `${name} at ${size}`).toBe(size);
    }
    await toLibrary(page);
  }
  expect(errors).toEqual([]);
});

test('the publisher\'s proportions are kept, the same in both books, at every setting', async ({ page }) => {
  const errors = await start(page);
  for (const [name, book] of [['relative', sizeBooks.relative], ['absolute', sizeBooks.absolute]]) {
    await readBook(page, book.opts);
    for (const size of [14, 20, 28]) {
      await setSize(page, size);
      await expect.poll(() => body(page), `${name} at ${size}`).toBe(size);
      expect(await h1(page) / size, `${name} h1 at ${size}`).toBeCloseTo(2, 2);
      expect(await h2(page) / size, `${name} h2 at ${size}`).toBeCloseTo(1.5, 2);
      expect(await small(page) / size, `${name} small at ${size}`).toBeCloseTo(0.8, 2);
      expect(await lead(page) / size, `${name} lead at ${size}`).toBeCloseTo(1.25, 2);
      // the hierarchy
      expect(await h1(page)).toBeGreaterThan(await h2(page));
      expect(await h2(page)).toBeGreaterThan(await body(page));
      expect(await body(page)).toBeGreaterThan(await small(page));
    }
    await toLibrary(page);
  }
  expect(errors).toEqual([]);
});

test('an inline size and an obsolete font size keep their proportion too', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, sizeBooks.legacy.opts);
  await setSize(page, 20);
  await expect.poll(() => body(page)).toBe(20);
  // 8px of the 12px text, 10px (font size 1) of it, in twentieths: 0.65 and 0.85
  expect(await caption(page) / 20).toBeCloseTo(0.65, 2);
  expect(await bookPage(page).locator('p', { hasText: 'For the reader' }).locator('[data-fs]').first().evaluate(e => parseFloat(getComputedStyle(e).fontSize)) / 20).toBeCloseTo(0.85, 2);
  expect(errors).toEqual([]);
});

test('a book that sets no size has body text at the setting and the headings by Quire\'s own proportions', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, sizeBooks.unsized.opts);
  await setSize(page, 20);
  await expect.poll(() => body(page)).toBe(20);
  await expect(bookPage(page).locator('[data-fs]')).toHaveCount(0);
  const unsized = [await h1(page), await h2(page)];
  await toLibrary(page);
  // the same text in a book of Quire's own making: its headings are the same
  await readBook(page, { title: 'Plain', author: 'Sizing', rawChapters: [{ body: '<h1>A Title</h1><h2>A Subtitle</h2><p>Body text of the first paragraph.</p>' }] });
  expect([await h1(page), await h2(page)]).toEqual(unsized);
  expect(unsized[0]).toBeGreaterThan(20);
  expect(errors).toEqual([]);
});

test('the dominant size on body alone, on a div, by html and rem, and by calc() each give body text at the setting', async ({ page }) => {
  const errors = await start(page);
  for (const name of ['onBody', 'onDiv', 'onHtml', 'onCalc']) {
    await readBook(page, sizeBooks[name].opts);
    await setSize(page, 20);
    await expect.poll(() => body(page), name).toBe(20);
    // h1 is 2 times the text in each (calc() is not read: 2em of the 16px
    // the text has, which is the text)
    expect(await h1(page) / 20, `${name} h1`).toBeCloseTo(2, 2);
    await toLibrary(page);
  }
  expect(errors).toEqual([]);
});

test('a part title page of headings does not change the scale of the chapter after it', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, sizeBooks.partTitle.opts);
  await setSize(page, 16);
  // the title page: 30pt and 20pt over the book's 10pt text, 3 and 2
  await expect.poll(() => fontSize(page, 'h1', 'Part One')).toBe(48);
  expect(await fontSize(page, 'h2', 'In which')).toBe(32);
  await chapterNamed(page, 'Second');
  await expect.poll(() => fontSize(page, 'p', 'Body text of the second chapter')).toBe(16);
  expect(await fontSize(page, 'h1', 'Another Title')).toBe(48);
  expect(errors).toEqual([]);
});

test('a 1px rule and a 400% rule are held to half and three times the text', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, sizeBooks.extremes.opts);
  await setSize(page, 24);
  await expect.poll(() => body(page)).toBe(24);
  expect(await fontSize(page, 'p', 'A tiny paragraph')).toBe(12);
  expect(await fontSize(page, 'p', 'A huge one')).toBe(72);
  expect(errors).toEqual([]);
});

test('only the size is read: the colour, ground, face, margin, alignment and line height of a book are still the reader\'s', async ({ page }) => {
  const errors = await start(page);
  const traits = () => bookPage(page).locator('p', { hasText: 'Body text of the first paragraph' }).first().evaluate(e => {
    const cs = getComputedStyle(e);
    return {
      color: cs.color, background: cs.backgroundColor, family: cs.fontFamily, textAlign: cs.textAlign,
      marginLeft: cs.marginLeft, marginTop: cs.marginTop, spacing: cs.marginBottom,
      lineHeight: parseFloat(cs.lineHeight) / parseFloat(cs.fontSize),
    };
  });
  await readBook(page, sizeBooks.unsized.opts);
  await setSize(page, 20);
  const plain = await traits();
  await toLibrary(page);
  await readBook(page, sizeBooks.everything.opts);
  await expect.poll(() => body(page)).toBe(20);
  expect(await traits()).toEqual(plain);
  expect(errors).toEqual([]);
});

test('the line height, paragraph spacing and margins follow the setting, and the place stays when the size changes', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, sizeBooks.relative.opts);
  await setSize(page, 16);
  const spacing = () => bookPage(page).locator('p', { hasText: BODY }).first().evaluate(e => {
    const cs = getComputedStyle(e);
    return { lineHeight: parseFloat(cs.lineHeight) / parseFloat(cs.fontSize), margin: parseFloat(cs.marginBottom) / parseFloat(cs.fontSize), padding: cs.paddingLeft };
  });
  const before = await spacing();
  // the setting's own line height (a multiple of the size) and paragraph spacing (in ems)
  expect(before.lineHeight).toBeGreaterThan(1.2);
  await setSize(page, 28);
  await expect.poll(() => body(page)).toBe(28);
  const after = await spacing();
  expect(after.lineHeight).toBeCloseTo(before.lineHeight, 2);
  expect(after.margin).toBeCloseTo(before.margin, 2);
  // the page keeps the paragraph it was on: turned to the second one's page, the size changed
  const second = 'Body text of the second paragraph';
  for (let turns = 0; turns < 40 && !(await onPage(page, second)); turns++) {
    await page.keyboard.press('ArrowRight');
    await page.waitForTimeout(350);
  }
  expect(await onPage(page, second)).toBe(true);
  await setSize(page, 20);
  await expect.poll(() => body(page)).toBe(20);
  await expect.poll(() => onPage(page, second)).toBe(true);
  await setSize(page, 14);
  await expect.poll(() => body(page)).toBe(14);
  await expect.poll(() => onPage(page, second)).toBe(true);
  expect(errors).toEqual([]);
});

test('a sheet linked from the chapter is read, stored or deflated, with the chapter\'s own style on top', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, sizeBooks.linked.opts);
  await setSize(page, 20);
  // p is 9pt (the text), h1 18pt in the linked sheet, h2 13.5pt in the chapter's style
  await expect.poll(() => body(page)).toBe(20);
  expect(await h1(page) / 20).toBeCloseTo(2, 2);
  expect(await h2(page) / 20).toBeCloseTo(1.5, 2);
  expect(errors).toEqual([]);
});

// Respect the publisher's sizes: the reader's size is the root the
// publisher's sizes are relative to, an absolute size is absolute (B's 9pt
// is 12px), and the same switch is kept, backed up and reset with the
// settings
test('respecting the publisher\'s sizes: A\'s text is the setting, B\'s is as the publisher set it, and the ratios still hold', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, sizeBooks.relative.opts);
  await setSize(page, 20);
  await openReadingSettings(page, 'Look');
  await expect(respectSwitch(page)).toHaveAttribute('aria-pressed', 'false');
  await respectSwitch(page).click();
  await expect(respectSwitch(page)).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('Escape');
  await expect.poll(() => body(page)).toBe(20);
  expect(await h1(page)).toBe(40);
  expect(await h2(page)).toBe(30);
  expect(await lead(page)).toBe(25);
  await toLibrary(page);
  await readBook(page, sizeBooks.absolute.opts);
  // B's 9pt is 12px, whatever the setting; its headings are 24px and 18px
  await expect.poll(() => body(page)).toBe(12);
  expect(await h1(page)).toBe(24);
  expect(await h2(page)).toBe(18);
  expect(await h1(page) / await body(page)).toBeCloseTo(2, 2);
  expect(await h2(page) / await body(page)).toBeCloseTo(1.5, 2);
  expect(await lead(page) / await body(page)).toBeCloseTo(1.25, 2);
  // the Size is the root the sizes are against: A's text follows it, and B's absolute size does not
  await setSize(page, 24);
  await expect.poll(() => body(page)).toBe(12);
  await toLibrary(page);
  await openBook(page, sizeBooks.relative.opts.title);
  await expect.poll(() => body(page)).toBe(24);
  // off again: both are the setting
  await openReadingSettings(page, 'Look');
  await respectSwitch(page).click();
  await expect(respectSwitch(page)).toHaveAttribute('aria-pressed', 'false');
  await page.keyboard.press('Escape');
  await expect.poll(() => body(page)).toBe(24);
  await toLibrary(page);
  await openBook(page, sizeBooks.absolute.opts.title);
  await expect.poll(() => body(page)).toBe(24);
  expect(errors).toEqual([]);
});

test('the switch is kept across a relaunch, in the backup, and is reset with the settings and brought back by Undo', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, sizeBooks.absolute.opts);
  await setSize(page, 20);
  await openReadingSettings(page, 'Look');
  await respectSwitch(page).click();
  await expect(respectSwitch(page)).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('Escape');
  await expect.poll(() => body(page)).toBe(12);
  // kept across a relaunch, which comes back to the book
  await reload(page);
  await expect(bookPage(page)).toBeVisible();
  await expect.poll(() => body(page)).toBe(12);
  await openReadingSettings(page, 'Look');
  await expect(respectSwitch(page)).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('Escape');
  // in the backup
  await toLibrary(page);
  await librarySettings(page);
  const backup = await exportedBackup(page);
  expect(JSON.parse(backup).settings.publisherSizes).toBe(1);
  const path = rawFile('quire-backup.json', backup);
  await settingsButton(page, 'Back').click();
  // reset with the settings, and brought back by Undo
  await openBook(page, sizeBooks.absolute.opts.title);
  await openReadingSettings(page, 'Look');
  await readingSettings(page).getByRole('button', { name: 'Reset reading settings', exact: true }).click();
  await expect(respectSwitch(page)).toHaveAttribute('aria-pressed', 'false');
  await page.keyboard.press('Escape');
  await expect.poll(() => body(page)).toBe(18);
  await page.getByRole('button', { name: 'Undo' }).click();
  await expect.poll(() => body(page)).toBe(12);
  await openReadingSettings(page, 'Look');
  await expect(respectSwitch(page)).toHaveAttribute('aria-pressed', 'true');
  // turned off by hand, then restored from the backup
  await respectSwitch(page).click();
  await expect(respectSwitch(page)).toHaveAttribute('aria-pressed', 'false');
  await page.keyboard.press('Escape');
  await toLibrary(page);
  await librarySettings(page);
  await restoreInput(page).setInputFiles([path]);
  await expect(dialog(page, 'Backup restored')).toBeVisible();
  await dialog(page, 'Backup restored').getByRole('button', { name: 'Done' }).click();
  await openBook(page, sizeBooks.absolute.opts.title);
  await expect.poll(() => body(page)).toBe(12);
  expect(JSON.parse(readFileSync(path, 'utf8')).settings.publisherSizes).toBe(1);
  expect(errors).toEqual([]);
});
