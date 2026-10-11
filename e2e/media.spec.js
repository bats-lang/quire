// Audio and video elements in a chapter (#424, #419). Decided from what
// readers do: Apple Books plays embedded audio and video (its asset
// guide), Kobo's iOS and Android apps do (its e-ink devices show the
// fallback content instead, Kobo's epub-spec notes, quoted on MobileRead),
// and Thorium, Foliate and Calibre's viewer are browser engines that play
// them with the engine's own controls. Quire is a browser page, so it does
// what they do: the element is made with the browser's controls, its file
// is the book's entry (a blob made on the JS side from the book's bytes),
// and nothing plays by itself. The suite's pub-cmt-mp3, -mp4 and -opus
// (must) want audio that can be heard. Leaving the chapter removes the
// element, which stops it.

import { test, expect } from './fixtures.js';
import { start, readBook, bookPage } from './helpers.js';
import { mediaBooks } from './media-books.js';

test('pub-cmt-mp3, pub-cmt-mp4, pub-cmt-opus (must): an audio or video element has the browser\'s controls and the book\'s file, and nothing plays by itself', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, mediaBooks.media.opts);
  const text = await bookPage(page).evaluate(doc => doc.innerText);
  expect(text).toContain('Before the audio.');
  expect(text).toContain('After the media.');
  const players = await bookPage(page).evaluate(doc => [...doc.querySelectorAll('audio, video')].map(e => ({
    tag: e.tagName, controls: e.controls, autoplay: e.autoplay, paused: e.paused, source: e.getAttribute('src') || '',
  })));
  expect(players.map(p => p.tag)).toEqual(['AUDIO', 'AUDIO', 'VIDEO']);
  for (const player of players) {
    expect(player.controls).toBe(true);
    expect(player.autoplay).toBe(false);
    expect(player.paused).toBe(true);
  }
  // the file is the book's: a blob, not an address of the web (the sources of the second
  // are given to the element itself)
  for (const player of players) expect(player.source).toMatch(/^blob:/);
  // the real clip is read: the browser knows its length without playing it
  const audio = bookPage(page).locator('audio').first();
  await expect.poll(() => audio.evaluate(a => a.readyState)).toBeGreaterThanOrEqual(1);
  expect(await audio.evaluate(a => a.duration)).toBeGreaterThan(0);
  expect(await audio.evaluate(a => a.paused)).toBe(true);
  expect(errors).toEqual([]);
});
