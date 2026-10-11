// The numbers of books in a series (#434). A series position is kept in
// hundredths, as Calibre keeps it (a float: 2.5 is a novella between
// volumes 2 and 3, 0 a prequel) and as FBReader writes it: the card and
// Book info show it as it was written without a trailing zero, the library
// sorts a series by it, and a book of the series with no number comes
// after those that have one. The books are in series-books.js, checked by
// epubcheck.spec.js.

import { test, expect } from './fixtures.js';
import {
  start, epubFile, rawFile, importFiles, importInput, card, cards, titles, reload, bookMenu, menuItem, dialog,
  chooseInSortMenu, librarySettings, settingsButton, restoreInput, exportedBackup, openBook, bookPage,
} from './helpers.js';
import { NOON, minutesLater, stores, sync, importFiles as importOn, unexpected } from './sync-devices.js';
import { seriesBooks, volumes, written, writtenTitle } from './series-books.js';

const file = name => epubFile(seriesBooks[name].opts);
const info = page => dialog(page, 'Book info');

/** The series line of a card ("Foundation · 2.5"), empty when it has none */
async function seriesLine(page, title) {
  const line = card(page, title).locator('.bser');
  return (await line.count()) === 0 ? '' : (await line.innerText()).trim();
}

/** Book info's series row for the book with title */
async function infoSeries(page, title) {
  await bookMenu(page, title);
  await menuItem(page, 'Book info').click();
  await expect(info(page)).toBeVisible();
  const row = info(page).locator('#info-series-row');
  const shown = await row.isVisible();
  const text = shown ? (await row.innerText()).replace(/\s+/g, ' ').trim() : null;
  await page.keyboard.press('Escape');
  await expect(info(page)).toBeHidden();
  return text;
}

for (const form of ['epub3', 'calibre']) {
  test(`volumes 1, 2, 2.5, 3 and 10 sort by their numbers, not by title, from ${form === 'epub3' ? 'group-position' : 'calibre:series_index'}`, async ({ page }) => {
    const errors = await start(page);
    const names = volumes.map(([, position]) => `${form} volume ${position}`);
    // imported out of order
    const order = [4, 2, 0, 3, 1];
    await importFiles(page, order.map(k => file(names[k])), 5);
    await chooseInSortMenu(page, 'Series');
    const prefix = form === 'epub3' ? 'Three' : 'Cal';
    const expected = volumes.map(([title]) => `${prefix} ${title}`);
    await expect.poll(() => titles(page)).toEqual(expected);
    // by the title they would be 10 before 2, and the novella first
    expect([...expected].sort()).not.toEqual(expected);
    await expect(card(page, `${prefix} A Novella`)).toContainText('Foundation · 2.5');
    await expect(card(page, `${prefix} Foundation Vol 10`)).toContainText('Foundation · 10');
    await expect(card(page, `${prefix} Foundation Vol 2`)).toContainText('Foundation · 2');
    await expect(card(page, `${prefix} Foundation Vol 2`)).not.toContainText('2.');
    // kept, and read back
    await reload(page);
    await expect.poll(() => titles(page)).toEqual(expected);
    await expect(card(page, `${prefix} A Novella`)).toContainText('Foundation · 2.5');
    expect(errors).toEqual([]);
  });
}

// The numbers as they are written: shown as the reader would write them (no
// trailing zero), sorted by value, and a text that is not a number is no
// number: shown with the series' name alone, sorted after the numbered
const asNumber = shown => (shown === '' ? null : Number(shown));

test('a position as it is written is shown without a trailing zero, in Book info too, and the books sort by value', async ({ page }) => {
  const errors = await start(page);
  const books = written.map(([name]) => `written ${name}`);
  await importFiles(page, books.map(file), books.length);
  for (const [k, [name, , shown]] of written.entries()) {
    const title = writtenTitle(k, name);
    const line = await seriesLine(page, title);
    expect(line, `${title}: ${line}`).toBe(shown === '' ? 'Written' : `Written · ${shown}`);
  }
  await chooseInSortMenu(page, 'Series');
  const expected = written.map(([name, , shown], k) => ({ title: writtenTitle(k, name), value: asNumber(shown) }))
    .sort((a, b) => (a.value === null) - (b.value === null) || (a.value ?? 0) - (b.value ?? 0) || (a.title < b.title ? -1 : 1))
    .map(b => b.title);
  await expect.poll(() => titles(page)).toEqual(expected);
  // Book info says what the card says
  for (const k of [0, 1, 2, 5, 6, 8, 13]) {
    const [name, , shown] = written[k];
    expect(await infoSeries(page, writtenTitle(k, name)), writtenTitle(k, name)).toBe(shown === '' ? 'Series Written' : `Series Written · ${shown}`);
  }
  expect(errors).toEqual([]);
});

test('an empty position, or one of spaces, is no number and the book is not refused', async ({ page }) => {
  const errors = await start(page);
  await importFiles(page, [file('empty position'), file('blank position')], 2);
  for (const title of ['Position empty', 'Position blank']) expect(await seriesLine(page, title)).toBe('Written');
  expect(errors).toEqual([]);
});

test('a position written the way Calibre writes it is shown without a trailing zero', async ({ page }) => {
  await start(page);
  const books = written.slice(0, 3).map(([name]) => `calibre written ${name}`);
  await importFiles(page, books.map(file), 3);
  for (const [k, [name, , shown]] of written.slice(0, 3).entries()) {
    expect(await seriesLine(page, writtenTitle(k, name, 'C'))).toBe(`Calibre Written · ${shown}`);
  }
});

test('a book of two series is shown in the first, with the position that refines it', async ({ page }) => {
  const errors = await start(page);
  const names = ['two series', 'set before series', 'positions out of order', 'epub3 and calibre'];
  await importFiles(page, names.map(file), 4);
  await expect(card(page, 'Two Series')).toContainText('First Series · 4');
  await expect(card(page, 'Two Series')).not.toContainText('Second Series');
  // a collection of the set type is not a series
  await expect(card(page, 'Set Before Series')).toContainText('Real Series · 3');
  await expect(card(page, 'Set Before Series')).not.toContainText('A Set Of Books');
  // each position goes with the collection it refines, whatever the order of the metas
  await expect(card(page, 'Positions Out Of Order')).toContainText('First Series · 4');
  // EPUB 3's series wins over Calibre's
  await expect(card(page, 'Epub3 And Calibre')).toContainText('Standard Series · 2');
  expect(await infoSeries(page, 'Two Series')).toBe('Series First Series · 4');
  // the book is the same book: it opens, and what is shown is read back
  await reload(page);
  await expect(card(page, 'Two Series')).toContainText('First Series · 4');
  await openBook(page, 'Two Series');
  await expect(bookPage(page)).toContainText('a short book of a series');
  expect(errors).toEqual([]);
});

test('books of a series with no number come after the numbered ones, by title, and books of no series last', async ({ page }) => {
  await start(page);
  const names = ['unnumbered zulu', 'no series', 'numbered second', 'unnumbered alpha', 'numbered first', 'calibre unnumbered'];
  await importFiles(page, names.map(file), 6);
  await chooseInSortMenu(page, 'Series');
  await expect.poll(() => titles(page)).toEqual(['Numbered First', 'Numbered Second', 'Alpha Unnumbered', 'Calibre Unnumbered', 'Zulu Unnumbered', 'Aaa Alone']);
    expect(await seriesLine(page, 'Alpha Unnumbered')).toBe('Mixed');
  expect(await infoSeries(page, 'Alpha Unnumbered')).toBe('Series Mixed');
  expect(await infoSeries(page, 'Aaa Alone')).toBeNull();
});

// ---- kept, backed up and synced ----

test('the position survives a reload, a backup and its restore, as 2.5 and not 2', async ({ page }) => {
  await start(page);
  await importFiles(page, [file('epub3 volume 2.5'), file('calibre volume 10')], 2);
  const novella = 'Three A Novella';
  await expect(card(page, novella)).toContainText('Foundation · 2.5');
  await reload(page);
  await expect(card(page, novella)).toContainText('Foundation · 2.5');
  // a backup holds no series (it is the book's own, read from its file), and a restore leaves the position as it is
  await librarySettings(page);
  const backup = await exportedBackup(page);
  await settingsButton(page, 'Done').click();
  expect(backup).not.toContain('"Foundation"');
  expect(backup).not.toMatch(/"(series|number|position)"/i);
  const path = rawFile('quire-backup.json', backup);
  await librarySettings(page);
  await restoreInput(page).setInputFiles([path]);
  await expect(dialog(page, 'Backup restored')).toBeVisible();
  await dialog(page, 'Backup restored').getByRole('button', { name: 'OK' }).click();
  await expect(card(page, novella)).toContainText('Foundation · 2.5');
  await expect(card(page, 'Cal Foundation Vol 10')).toContainText('Foundation · 10');
});

test('a book imported again takes its position from the file, 2.5 and not 2', async ({ page }) => {
  await start(page);
  const same = file('epub3 volume 2.5');
  await importFiles(page, [same], 1);
  // the same file again: Replace
  await importInput(page).setInputFiles([same]);
  await dialog(page, 'Already in library').getByRole('button', { name: 'Replace' }).click();
  await expect(card(page, 'Three A Novella')).toContainText('Foundation · 2.5');
  await expect(cards(page)).toHaveCount(1);
});

test('the position on another device is the one its own copy of the book has, 2.5 and not 2', async ({ browser }) => {
  const store = stores.webdav;
  const server = store.make();
  const a = await store.device(browser, server, NOON);
  const b = await store.device(browser, server, minutesLater(NOON, 1));
  const novella = file('epub3 volume 2.5');
  for (const d of [a, b]) {
    await importOn(d.page, [novella], 1);
    await store.join(d, server);
  }
  await sync(store, server, a);
  await sync(store, server, b);
  for (const d of [a, b]) await expect(card(d.page, 'Three A Novella')).toContainText('Foundation · 2.5');
  // the sync file keeps places, shelves and notes, and not the book's own series
  expect(String(store.bytes(server))).not.toContain('"Foundation"');
  expect(String(store.bytes(server))).not.toMatch(/"(series|number|position)"/i);
  expect(unexpected(a)).toEqual([]);
  await a.context.close();
  await b.context.close();
});
