// What the reader is told when something fails, and when a copy is
// made: the error banner (an alert) in both views, a failed save said
// once a session, a chapter that cannot be read, and the copy status.

import { test, expect, onAndroid } from './fixtures.js';
import {
  expectBannerSaysWhatToDo, start, readBook, importFiles, epubFile, card, place, chapterTitle, showChrome, control, dialog,
  librarySearch, selectText, selectionButton, bookPage, chapters, libraryShown,
} from './helpers.js';

const alert = page => page.getByRole('alert');
const unreadable = /(Chapter \d+|The contents) of this book could not be read\. Choose another chapter in the contents, or import the book again and choose Replace\./;
// the banners' words by where Quire runs: none says "browser" in the app
const storageFull = testInfo => onAndroid(testInfo)
  ? 'Quire could not save your changes: the device\'s storage may be full. Free some space on the device and try again.'
  : 'Quire could not save your changes: the browser\'s storage may be full. Free some space in the browser and try again.';
const notStored = (testInfo, title) =>
  `${title} is open, but its file could not be stored, so it will not open next time. Free some space ${onAndroid(testInfo) ? 'on the device' : 'in the browser'} and try again.`;
const notCopied = testInfo => `The text could not be copied: the ${onAndroid(testInfo) ? 'device' : 'browser'} did not allow it.`;

/** Every IndexedDB put fails from now on, as when storage is full: its
    transaction aborts (the one failure event the bridge listens for).
    window.putsFailed counts them */
async function failPuts(page) {
  await page.evaluate(() => {
    window.putsFailed = 0;
    IDBObjectStore.prototype.put = function () {
      window.putsFailed++;
      this.transaction.abort();
      return {};
    };
  });
}

const putsFailed = page => page.evaluate(() => window.putsFailed);

test('a chapter that cannot be read leaves the reader on its page, with the banner', async ({ page }, testInfo) => {
  const errors = await start(page);
  // chapter 1 is one page long, so the next page is chapter 2's
  await readBook(page, {
    title: 'Damaged Book', author: 'Notice Tests',
    rawChapters: [{ body: '<h1>Part 1</h1><p>Para 1.0 short</p>' }, ...chapters(3).slice(1)],
    damagedChapters: [2],
  });
  expect(await place(page)).toMatchObject({ ch: 1, p: 1 });
  await expect(alert(page)).toBeHidden();
  // a turn into it
  await page.keyboard.press('ArrowRight');
  await expect(alert(page)).toBeVisible();
  await expect(alert(page)).toContainText(unreadable);
  await expectBannerSaysWhatToDo(page, testInfo);
  // the banner is shown over the reader, which stays on the page it was on
  await expect(bookPage(page)).toBeVisible();
  await expect(bookPage(page)).toContainText('Para 1.0 short');
  expect(await place(page)).toMatchObject({ ch: 1, p: 1 });
  await alert(page).getByRole('button', { name: 'Dismiss' }).click();
  await expect(alert(page)).toBeHidden();
  // a jump to it from the contents: the same
  await showChrome(page);
  await control(page, 'Contents').click();
  const contents = dialog(page, 'Contents');
  await contents.getByRole('tabpanel', { name: 'Contents' }).getByRole('button', { name: 'Chapter 2' }).click();
  await expect(alert(page)).toContainText(unreadable);
  await expectBannerSaysWhatToDo(page, testInfo);
  await expect(bookPage(page)).toContainText('Para 1.0 short');
  await expect(chapterTitle(page)).toHaveText('Chapter 1');
  // the chapter after it still opens
  await alert(page).getByRole('button', { name: 'Dismiss' }).click();
  await showChrome(page);
  await control(page, 'Contents').click();
  await contents.getByRole('tabpanel', { name: 'Contents' }).getByRole('button', { name: 'Chapter 3' }).click();
  await expect(chapterTitle(page)).toHaveText('Chapter 3');
  await expect(alert(page)).toBeHidden();
  expect(errors).toEqual([]);
});

test('a book whose saved place cannot be read goes back to the library, with the banner', async ({ page }, testInfo) => {
  await start(page);
  await importFiles(page, [epubFile({ title: 'Unopenable', author: 'Notice Tests', rawChapters: chapters(2), damagedChapters: [1] })], 1);
  await card(page, 'Unopenable').click();
  await expect(alert(page)).toContainText(unreadable);
  await expectBannerSaysWhatToDo(page, testInfo);
  await expect(libraryShown(page)).toBeVisible();
});

test('a failed save shows the storage message once a session', async ({ page }, testInfo) => {
  await start(page);
  await readBook(page, { title: 'Full Disk', author: 'Notice Tests', rawChapters: chapters(2) });
  await failPuts(page);
  // the place is saved at each page turn
  await page.keyboard.press('ArrowRight');
  await expect(alert(page)).toBeVisible();
  await expect(alert(page)).toContainText(storageFull(testInfo));
  await expectBannerSaysWhatToDo(page, testInfo);
  await alert(page).getByRole('button', { name: 'Dismiss' }).click();
  await expect(alert(page)).toBeHidden();
  // later saves fail too, and are not said again
  const before = await putsFailed(page);
  await page.keyboard.press('ArrowRight');
  await page.keyboard.press('ArrowRight');
  await expect.poll(() => putsFailed(page)).toBeGreaterThan(before);
  // a failed put is told when its transaction aborts, a task after the
  // put: past that, the banner would be up
  await page.evaluate(() => new Promise(resolve => setTimeout(resolve, 500)));
  await expect(alert(page)).toBeHidden();
});

test('a book whose file cannot be stored is named in the banner', async ({ page }, testInfo) => {
  await start(page);
  await failPuts(page);
  await importFiles(page, [epubFile({ title: 'Never Kept', author: 'Notice Tests', rawChapters: chapters(1) })], 1);
  await expect(alert(page)).toContainText(notStored(testInfo, 'Never Kept'));
  await expectBannerSaysWhatToDo(page, testInfo);
});

test('Copy says "Copied" for a moment, and a copy the browser refuses is said in the banner', async ({ page, context }, testInfo) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await start(page);
  await readBook(page, { title: 'Copied Book', author: 'Notice Tests', rawChapters: chapters(1) });
  await selectText(page, 0, 8);
  await selectionButton(page, 'Copy').click();
  const copied = page.getByRole('status').filter({ hasText: 'Copied' });
  await expect(copied).toBeVisible();
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText())).toBe('Para 1.0');
  // it is not the Undo toast, and it goes on its own
  await expect(page.getByRole('button', { name: 'Undo' })).toBeHidden();
  await expect(copied).toBeHidden({ timeout: 5000 });
  await expect(alert(page)).toBeHidden();
  // refused
  await page.evaluate(() => { navigator.clipboard.writeText = () => Promise.reject(new Error('denied')); });
  await selectText(page, 0, 8);
  await selectionButton(page, 'Copy').click();
  await expect(alert(page)).toContainText(notCopied(testInfo));
  await expectBannerSaysWhatToDo(page, testInfo);
  await expect(copied).toBeHidden();
});
