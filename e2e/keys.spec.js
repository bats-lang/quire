// The keys a Bluetooth page turner or a presenter's remote sends (#412):
// the arrows, Page Up and Down, Space, the media keys of a turner's
// multimedia mode, the volume keys; in every reading mode; and when they
// are not the page's.
//
// Decided (issue 412), from what the remotes send: the DIY and the
// common page turners present a keyboard of the left and right arrow keys
// (a Kobo user's report), the DuRoBo Moodi sends the volume keys in its
// reading mode and previous and next track in its multimedia mode (a
// review at geardiary.com), and presenter remotes send Page Up and Down.
// Enter is not a page key: it follows the focused link. So Quire turns the
// page with the arrows, Page Up and Down, Space (Shift for back), the
// volume keys when the reader chooses, and the media keys MediaTrackNext
// and MediaTrackPrevious.

import { test, expect } from './fixtures.js';
import {
  start, readBook, place, chapters, bookPage, dialog, control, showChrome, fixedLayoutBook, readFixed, fixedPlace,
  openReadingSettings, readingSettings, japaneseChapters,
} from './helpers.js';

const book = { title: 'Keyed', author: 'Keys', rawChapters: chapters(1, 60) };

/** The keydown a browser sends the page for a key Playwright has no name for */
const press = (page, key, init = {}) => page.evaluate(([k, i]) => {
  const event = new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true, ...i });
  document.dispatchEvent(event);
  return event.defaultPrevented;
}, [key, init]);

test('the page keys and the media keys turn the page, each by one page', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, book);
  const first = await place(page);
  for (const [key, by] of [['PageDown', 1], [' ', 1], ['ArrowRight', 1], ['MediaTrackNext', 1], ['PageUp', -1], ['MediaTrackPrevious', -1], ['ArrowLeft', -1]]) {
    const before = await place(page);
    await press(page, key);
    await expect.poll(async () => (await place(page)).p, key).toBe(before.p + by);
  }
  // four on and three back: one on
  expect((await place(page)).p).toBe(first.p + 1);
  // Shift+Space goes back
  await press(page, ' ', { shiftKey: true });
  await expect.poll(async () => (await place(page)).p).toBe(first.p);
  expect(errors).toEqual([]);
});

test('a key pressed again and again turns one page for each press, none skipped', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  const first = await place(page);
  for (let k = 0; k < 4; k++) await press(page, 'PageDown');
  await expect.poll(async () => (await place(page)).p).toBe(first.p + 4);
  // held down: the browser's repeats are presses
  for (let k = 0; k < 3; k++) await press(page, 'MediaTrackPrevious', { repeat: k > 0 });
  await expect.poll(async () => (await place(page)).p).toBe(first.p + 1);
});

test('the page keys scroll, turn a vertical book and a fixed-layout book', async ({ page }) => {
  await start(page);
  // scrolled
  await readBook(page, book);
  await openReadingSettings(page, 'Page');
  await readingSettings(page).getByRole('group', { name: 'Layout' }).getByRole('button', { name: 'Scroll', exact: true }).click();
  await page.keyboard.press('Escape');
  const top = () => bookPage(page).evaluate(doc => doc.scrollTop);
  const before = await top();
  await press(page, 'PageDown');
  await expect.poll(top).toBeGreaterThan(before);
  await press(page, 'PageUp');
  await expect.poll(top).toBe(before);
});

test('a vertical book turns its pages by the page keys, forward to the left', async ({ page }) => {
  await start(page);
  await readBook(page, { title: '縦', author: 'Keys', language: 'ja', rtl: true, rawChapters: japaneseChapters(1, 40) });
  const first = await place(page);
  await press(page, 'PageDown');
  await expect.poll(async () => (await place(page)).p).toBe(first.p + 1);
  await press(page, 'MediaTrackPrevious');
  await expect.poll(async () => (await place(page)).p).toBe(first.p);
});

test('a fixed-layout book turns its pages by the page keys', async ({ page }) => {
  await start(page);
  await readFixed(page, fixedLayoutBook('Fixed Keys', 5));
  const first = await fixedPlace(page);
  await press(page, 'PageDown');
  await expect.poll(() => fixedPlace(page)).not.toEqual(first);
  await press(page, 'MediaTrackNext');
  const second = await fixedPlace(page);
  await press(page, 'PageUp');
  await expect.poll(() => fixedPlace(page)).not.toEqual(second);
});

test('keys are not the page\'s while a dialog, a panel or a text field has the focus', async ({ page }) => {
  await start(page);
  await readBook(page, book);
  const at = await place(page);
  // the search panel's field: typing a space and keys are text
  await page.keyboard.press('/');
  const field = dialog(page, 'Search in book').getByRole('searchbox', { name: 'Search in book' });
  await expect(field).toBeFocused();
  await page.keyboard.type(' ab');
  await page.keyboard.press('PageDown');
  await page.keyboard.press('ArrowRight');
  await page.waitForTimeout(300);
  expect(await place(page)).toEqual(at);
  expect(await field.inputValue()).toBe(' ab');
  await page.keyboard.press('Escape');
  // the contents panel: its list is not the page
  await showChrome(page);
  await control(page, 'Contents').click();
  await expect(dialog(page, 'Contents')).toBeVisible();
  await press(page, 'MediaTrackNext');
  await page.waitForTimeout(300);
  expect(await place(page)).toEqual(at);
  await page.keyboard.press('Escape');
});

test('a volume key is the volume\'s while a dialog or panel is open, with the switch on', async ({ page }) => {
  await page.addInitScript(() => { window.Capacitor = { isNativePlatform: () => true, Plugins: {} }; });
  await start(page);
  await readBook(page, book);
  await openReadingSettings(page, 'Turning');
  await readingSettings(page).getByRole('button', { name: 'Turn pages with volume keys', exact: true }).click();
  await page.keyboard.press('Escape');
  const at = await place(page);
  await press(page, 'AudioVolumeDown');
  await expect.poll(async () => (await place(page)).p).toBe(at.p + 1);
  // with a panel open the key is left to the system
  await showChrome(page);
  await control(page, 'Contents').click();
  await expect(dialog(page, 'Contents')).toBeVisible();
  const prevented = await press(page, 'AudioVolumeDown');
  await page.waitForTimeout(300);
  expect((await place(page)).p).toBe(at.p + 1);
  expect(prevented).toBe(false);
});
