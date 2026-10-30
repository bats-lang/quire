// A file handed to the app (the Android "Open with" and "Share to", the installed web app's
// file handler and share target) opens on its book, whatever the app showed before (#959):
// on a cold start and on a running app, from the library, a book, a sheet over the reader or
// the Settings screen; a book the library already holds is opened where it was left, no
// question asked; a file that is not a book is said on its own and the screen is as it was.

import { test, expect } from './fixtures.js';
import {
  start, epubFile, rawFile, importFiles, openBook, pageShown, toLibrary, place, bookPage, chapters, cards,
  libraryShown, dialog, openSettings, readingSettings, librarySettings, settingsScreen,
} from './helpers.js';

const bookOf = (title, tag) => epubFile({ title, author: 'Intent Open', rawChapters: chapters(3, 20, tag) });

const served = (page, name, file) =>
  page.route(`**/_capacitor_file_/${name}`, r => r.fulfill({ path: file, contentType: 'application/octet-stream' }));

const handOver = (page, name, fileName) =>
  page.evaluate(([n, f]) => globalThis.batsNative.deliverFile('/_capacitor_file_/' + n, f), [name, fileName]);

// the activity's one hand-over as the app starts (bridge's batsNative is retried until it is there),
// not repeated when the page is loaded again
const handedAtStart = (page, name, fileName) => page.addInitScript(([n, f]) => {
  if (sessionStorage.getItem('handed-at-start-' + n)) return;
  sessionStorage.setItem('handed-at-start-' + n, 'yes');
  const handOverNow = () => {
    if (globalThis.batsNative) globalThis.batsNative.deliverFile('/_capacitor_file_/' + n, f);
    else setTimeout(handOverNow, 20);
  };
  handOverNow();
}, [name, fileName]);

const shows = async (page, tag) => {
  await pageShown(page);
  await expect(bookPage(page)).toContainText(`${tag} 1.0`);
};

/** A book imported and open, turned on to a page after its first */
async function readingTurned(page, title, tag) {
  await importFiles(page, [bookOf(title, tag)], (await cards(page).count()) + 1);
  await openBook(page, title);
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(2);
  return place(page);
}

test('a cold start with a file opens its book, not the book that was open', async ({ page }) => {
  const errors = await start(page);
  await readingTurned(page, 'Alpha Book', 'Alpha');
  await served(page, 'cold', bookOf('Bravo Book', 'Bravo'));
  await handedAtStart(page, 'cold', 'cold.epub');
  await page.reload();
  await shows(page, 'Bravo');
  expect(await place(page)).toMatchObject({ ch: 1, p: 1 });
  await expect(bookPage(page)).not.toContainText('Alpha 1.');
  await toLibrary(page);
  await expect(cards(page)).toHaveCount(2);
  expect(errors).toEqual([]);
});

test('a file handed over while a book is open opens its book, over a sheet too', async ({ page }) => {
  const errors = await start(page);
  await readingTurned(page, 'Alpha Book', 'Alpha');
  await openSettings(page);
  await served(page, 'running', bookOf('Bravo Book', 'Bravo'));
  await handOver(page, 'running', 'running.epub');
  await shows(page, 'Bravo');
  await expect(readingSettings(page)).toBeHidden();
  expect(await place(page)).toMatchObject({ ch: 1, p: 1 });
  expect(errors).toEqual([]);
});

test('a file handed over while the library is shown with Settings over it opens its book', async ({ page }) => {
  const errors = await start(page);
  await importFiles(page, [bookOf('Alpha Book', 'Alpha')], 1);
  await librarySettings(page);
  await expect(settingsScreen(page)).toBeVisible();
  await served(page, 'from-settings', bookOf('Bravo Book', 'Bravo'));
  await handOver(page, 'from-settings', 'from-settings.epub');
  await shows(page, 'Bravo');
  await expect(settingsScreen(page)).toBeHidden();
  expect(errors).toEqual([]);
});

// A book the library holds is its file again (the library knows a file by its contents), so there
// is nothing to replace and the reader asked for the book, not a question: it opens where it was
// left, as Apple Books, Moon+ Reader and KOReader open a file they hold
test('a file of a book the library holds opens that book where it was left, with no question', async ({ page }) => {
  const errors = await start(page);
  const bravo = bookOf('Bravo Book', 'Bravo');
  await importFiles(page, [bravo], 1);
  await openBook(page, 'Bravo Book');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(2);
  const left = await place(page);
  await toLibrary(page);
  await readingTurned(page, 'Alpha Book', 'Alpha');
  await served(page, 'held', bravo);
  await handOver(page, 'held', 'held.epub');
  await pageShown(page);
  await expect(bookPage(page)).toContainText('Bravo 1.');
  expect(await place(page)).toEqual(left);
  await expect(dialog(page, 'Already in library')).toBeHidden();
  await toLibrary(page);
  await expect(cards(page)).toHaveCount(2);
  expect(errors).toEqual([]);
});

test('a file that is not a book is said, and the book that was open is open at its place', async ({ page }) => {
  const errors = await start(page);
  const left = await readingTurned(page, 'Alpha Book', 'Alpha');
  await served(page, 'junk', rawFile('notes.epub', Buffer.from('this is not a zip file at all')));
  await handOver(page, 'junk', 'notes.epub');
  await expect(page.getByRole('alert')).toContainText('is not an EPUB');
  await pageShown(page);
  await expect(bookPage(page)).toContainText('Alpha 1.');
  await expect.poll(async () => JSON.stringify(await place(page))).toBe(JSON.stringify(left));
  expect(errors.filter(e => !e.includes('Failed to load resource'))).toEqual([]);
});

test('a cold start with a file that is not a book says so and keeps the book that was open', async ({ page }) => {
  const errors = await start(page);
  const left = await readingTurned(page, 'Alpha Book', 'Alpha');
  // the place is kept when the reader leaves the book: the reload below comes back to it
  await toLibrary(page);
  await openBook(page, 'Alpha Book');
  expect(await place(page)).toEqual(left);
  await served(page, 'junk-start', rawFile('notes.epub', Buffer.from('this is not a zip file at all')));
  await handedAtStart(page, 'junk-start', 'notes.epub');
  await page.reload();
  await expect(page.getByRole('alert')).toContainText('is not an EPUB');
  await pageShown(page);
  await expect(bookPage(page)).toContainText('Alpha 1.');
  await expect.poll(async () => JSON.stringify(await place(page))).toBe(JSON.stringify(left));
  expect(errors.filter(e => !e.includes('Failed to load resource'))).toEqual([]);
});

test('a file that is not a book, handed over to the library, leaves the library as it was', async ({ page }) => {
  const errors = await start(page);
  await importFiles(page, [bookOf('Alpha Book', 'Alpha')], 1);
  await served(page, 'junk-library', rawFile('notes.epub', Buffer.from('this is not a zip file at all')));
  await handOver(page, 'junk-library', 'notes.epub');
  await expect(page.getByRole('alert')).toContainText('is not an EPUB');
  await expect(libraryShown(page)).toBeVisible();
  await expect(bookPage(page)).toBeHidden();
  await expect(cards(page)).toHaveCount(1);
  expect(errors.filter(e => !e.includes('Failed to load resource'))).toEqual([]);
});
