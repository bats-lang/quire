// Every screen, sheet, menu and dialog of the app, opened one by one,
// each closed again one step back (quire#333): layout.spec.js checks
// each one's layout as it is shown, back.spec.js that Back goes exactly
// one step from each. Then every dialog the app has made must have
// been one of those shown, so a screen added later is walked here or
// this fails, naming it.

import { expect } from './fixtures.js';
import {
  start, epubFile, importFiles, readBook, showChrome, chapters, bookPage,
  libraryMenu, menuItem, dialog, librarySettings, settingsScreen,
  settingsButton, bookMenu, clickControl, topBar,
  readingSettings, openReadingSettings, selectText, rawFile,
} from './helpers.js';
import { solidPng } from './create-epub.js';
import { createStardict } from './create-stardict.js';

/** The Android app's plugins, played (Capacitor's SystemBars, the
    rotation lock, the brightness), so the screens show the app's own
    controls; each call kept in window.calls */
export function appPlayed() {
  window.calls = [];
  const call = name => a => { window.calls.push(name + (a ? ' ' + JSON.stringify(a) : '')); return Promise.resolve(); };
  window.Capacitor = { isNativePlatform: () => true, Plugins: {
    SystemBars: { hide: call('hide'), show: call('show') },
    ScreenOrientation: { lock: call('lock'), unlock: call('unlock') },
    ScreenBrightness: { setBrightness: call('brightness') },
  } };
}

/** Walks every screen: look(screen) is called on each as it is shown
    (named), and back() closes the one on top, one step back */
export async function walkEveryScreen(page, { look, back }) {
  // Project Gutenberg's catalogue, played: one page holding one book
  await page.route('https://www.gutenberg.org/**', route => route.fulfill({
    status: 200, headers: { 'Access-Control-Allow-Origin': '*' }, contentType: 'application/atom+xml',
    body: '<?xml version="1.0" encoding="UTF-8"?><feed xmlns="http://www.w3.org/2005/Atom"><id>urn:walk</id>' +
      '<title>A Catalogue With A Rather Long Name</title><updated>2026-10-01T00:00:00Z</updated>' +
      '<entry><title>A Book With A Rather Long Title</title><id>walked</id><author><name>Someone</name></author>' +
      '<link rel="http://opds-spec.org/acquisition" href="/walked.epub" type="application/epub+zip"/></entry></feed>',
  }));
  await start(page);
  const seen = new Set();
  const check = async screen => {
    await look(screen);
    for (const id of await page.evaluate(() => [...document.querySelectorAll('[role=dialog]')]
      .filter(e => e.checkVisibility() && e.getClientRects().length > 0).map(e => e.id))) seen.add(id);
  };
  await check('the empty library');
  await importFiles(page, [
    epubFile({ title: 'A Rather Long Title For A Book That Goes On And On', author: 'Someone With A Rather Long Name' }),
    epubFile({ title: 'Short', author: 'S' }),
  ], 2);
  await check('the library');
  await bookMenu(page, 'Short');
  await check('the book menu');
  await menuItem(page, 'Collections').click();
  await expect(dialog(page, 'Collections')).toBeVisible();
  await check('the collections panel');
  await dialog(page, 'Collections').getByRole('button', { name: 'New collection' }).click();
  await expect(dialog(page, 'New collection')).toBeVisible();
  await check('the new collection dialog');
  await back();
  await back();
  await bookMenu(page, 'Short');
  await menuItem(page, 'Book info').click();
  await expect(dialog(page, 'Book info')).toBeVisible();
  await check('book info');
  await back();
  await libraryMenu(page);
  await check('the library menu');
  await back();
  for (const name of ['Reading statistics', 'Catalogues', 'About Quire']) {
    await libraryMenu(page);
    await menuItem(page, name).click();
    await expect(page.getByRole('dialog', { name: name === 'About Quire' ? 'About Quire' : name, exact: true })).toBeVisible();
    await check(name);
    await back();
  }
  await libraryMenu(page);
  await menuItem(page, 'Catalogues').click();
  await dialog(page, 'Catalogues').getByRole('group', { name: 'Project Gutenberg' }).getByRole('button', { name: 'Project Gutenberg' }).click();
  const browsed = page.getByRole('dialog').filter({ has: page.getByRole('button', { name: 'Close catalogue' }) });
  await expect(browsed.getByRole('group', { name: 'A Book With A Rather Long Title' })).toBeVisible();
  await check('a catalogue\'s page');
  await browsed.getByRole('button', { name: 'Close catalogue' }).click();
  await expect(browsed).toBeHidden();
  await librarySettings(page);
  await check('Settings');
  // a dictionary, so the Dictionaries screen lists one and a word is looked up below
  const made = createStardict({ name: 'Pocket English', entries: [{ word: 'ephemeral', article: 'lasting a very short time' }] });
  await settingsButton(page, 'Dictionaries ›').click();
  await page.getByLabel('Import dictionary').setInputFiles([
    rawFile('walk.ifo', made.ifo), rawFile('walk.idx', made.idx), rawFile('walk.dict', made.dict)]);
  await expect(dialog(page, 'Dictionaries').getByRole('status')).toHaveText('Dictionary added.', { timeout: 30000 });
  await back();
  for (const row of ['Reading ›', 'Sync ›', 'Dictionaries ›', 'About Quire ›']) {
    await settingsButton(page, row).click();
    await expect(page.getByRole('dialog', { name: row.replace(' ›', ''), exact: true })).toBeVisible();
    await check(row);
    await back();
  }
  await back();
  await expect(settingsScreen(page)).toBeHidden();
  await bookMenu(page, 'Short');
  await menuItem(page, 'Move to Trash').click();
  await libraryMenu(page);
  await menuItem(page, 'Empty Trash').click();
  await expect(dialog(page, 'Empty the Trash?')).toBeVisible();
  await check('the Empty the Trash dialog');
  await back();
  // a note and a picture in its second chapter, so the note and the
  // picture's viewer open (shown last: a tap in the page's middle,
  // which brings up the bars, would open the picture)
  await readBook(page, {
    title: 'A Rather Long Title, Read', author: 'L',
    rawChapters: [...chapters(1), { body: '<p>ephemeral claims<a epub:type="noteref" href="#n1">1</a>.</p><p><img src="images/map.png" alt="the map"/></p>' +
      '<aside epub:type="footnote" id="n1"><p>The note.</p></aside>' }],
    extraImages: [{ name: 'images/map.png', data: solidPng(120, 120) }],
  });
  await showChrome(page);
  await check('the reader with its bars');
  for (const name of ['Contents', 'Annotations']) {
    await clickControl(page, name);
    await expect(dialog(page, name)).toBeVisible();
    await check(name);
    await back();
  }
  for (const tab of ['Look', 'Page', 'Turning', 'Read aloud']) {
    await openReadingSettings(page, tab);
    await check(`Reading settings, ${tab}`);
  }
  // each toggle of the Page tab on, too: its look on is checked as well
  await openReadingSettings(page, 'Page');
  for (const name of ['Full screen', 'Lock rotation']) {
    const toggle = readingSettings(page).getByRole('button', { name, exact: true });
    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-pressed', 'true');
  }
  await check('Reading settings, Page, its switches on');
  await back();
  await showChrome(page);
  await topBar(page).getByRole('button', { name: 'Search in book' }).click();
  await expect(dialog(page, 'Search in book')).toBeVisible();
  await check('Search in book');
  await back();
  await showChrome(page);
  await topBar(page).getByRole('button', { name: 'Settings' }).click();
  await check('Settings over the reader');
  await back();
  // the note, the picture and a word looked up, in the second chapter
  const map = bookPage(page).getByRole('img', { name: 'the map' });
  // (read from the page: the picture is not there until its chapter is)
  const shown = () => page.evaluate(() => [...document.querySelectorAll('[role=document] img[alt="the map"]')].some(i => {
    const r = i.getBoundingClientRect();
    return r.width > 0 && r.left >= 0 && r.right <= innerWidth && r.top >= 0 && r.bottom <= innerHeight;
  }));
  for (let turn = 0; turn < 60 && !(await shown()); turn++) {
    await page.keyboard.press('ArrowRight');
    await page.waitForTimeout(400);
  }
  await expect(map).toBeInViewport();
  await bookPage(page).getByRole('link', { name: '1', exact: true }).click();
  await expect(dialog(page, 'Footnote')).toBeVisible();
  await check('a footnote');
  await back();
  await expect.poll(() => map.evaluate(i => i.naturalWidth)).toBe(120);
  await map.click();
  await expect(dialog(page, 'Image')).toBeVisible();
  await check('the picture viewer');
  await back();
  await selectText(page, 0, 9);
  await expect(page.getByRole('toolbar', { name: 'Selection' })).toBeVisible();
  await check('the selection\'s toolbar');
  await page.getByRole('toolbar', { name: 'Selection' }).getByRole('button', { name: 'Look up', exact: true }).click();
  await expect(dialog(page, 'Dictionary')).toBeVisible();
  await check('a word looked up');
  await back();
  const unwalked = await page.evaluate(seen => [...document.querySelectorAll('[role=dialog]')]
    .map(e => e.id).filter(id => !seen.includes(id)), [...seen]);
  expect(unwalked, 'screens this walk never checked: walk them here').toEqual([]);
}
