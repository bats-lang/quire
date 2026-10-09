// Audio and video elements in a chapter (#424). Decided from what readers
// do: Apple Books plays embedded audio and video (its asset guide), Kobo's
// iOS and Android apps do and its e-ink devices show the fallback content
// (Kobo's epub-spec notes, quoted on MobileRead), Thorium is a browser
// engine. Quire's bindings to the DOM have no `controls`, `poster` or
// `<source>`, so a media element cannot be made playable from the book's
// file without extending them (a p3 issue is filed): Quire does what Kobo's
// e-ink devices do, shows the fallback content, and says in a line that the
// media is not played, so no element is an empty box. Nothing plays by
// itself, and no media element is made, so leaving the chapter or the book
// has nothing to stop.

import { test, expect } from './fixtures.js';
import { start, readBook, bookPage } from './helpers.js';
import { mediaBooks } from './media-books.js';

const LINE = 'Audio or video: Quire does not play it.';

const line = (page, id) => bookPage(page).evaluate((doc, id) => {
  const e = [...doc.querySelectorAll('.media-fallback')][id];
  return getComputedStyle(e, '::before').content;
}, id);

test('an audio or video element shows its fallback content and a line that it is not played; no media element is made', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, mediaBooks.media.opts);
  const text = await bookPage(page).evaluate(doc => doc.innerText);
  expect(text).toContain('Fallback words for the audio.');
  expect(text).toContain('Fallback words for the video.');
  expect(text).toContain('Before the audio.');
  expect(text).toContain('After the media.');
  // the line, drawn before each element, saying it is not played
  for (const index of [0, 1, 2]) expect(await line(page, index)).toBe(`"${LINE}"`);
  // no element is an empty box: the one with no fallback words has the line
  const heights = await bookPage(page).evaluate(doc => [...doc.querySelectorAll('.media-fallback')].map(e => e.getBoundingClientRect().height));
  for (const height of heights) expect(height).toBeGreaterThan(10);
  // nothing is playable: no media element in the page, so nothing plays or autoplays
  expect(await bookPage(page).evaluate(doc => doc.querySelectorAll('audio, video').length)).toBe(0);
  expect(await page.evaluate(() => [...document.querySelectorAll('audio')].filter(a => !a.paused).length)).toBe(0);
  expect(errors).toEqual([]);
});
