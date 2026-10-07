// Screenshots of the happy path, for #293: each path (a describe) is its
// own flow, reusing the e2e suite's helpers; each shot is
// shots/<path>/<NN-name>/<viewport>-<theme>.png. A shot that cannot be
// taken is noted in shots/failed.txt, not fatal.

import { test, expect } from '../e2e/fixtures.js';
import { appendFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import {
  start, importFiles, epubFile, rawFile, readBook, openBook, toLibrary, showChrome, clickControl, chapters,
  japaneseChapters, libraryMenu, menuItem, dialog, librarySettings, settingsScreen, settingsButton, bookMenu,
  openReadingSettings, readingSettings, selectText, selectionButton, bookPage, card, cards, control, topBar,
  fixedLayoutBook, readFixed, importInput,
} from '../e2e/helpers.js';
import { createStardict } from '../e2e/create-stardict.js';
import { solidPng } from '../e2e/create-epub.js';
import { syncSteps } from '../e2e/walk.js';

const THEME = process.env.THEME || 'light';
const OUT = join(process.cwd(), 'shots');

/** Light is noon, dark is 23:00, with the theme on Auto, which turns to Night then */
async function theme(page) {
  await page.clock.setFixedTime(new Date(THEME === 'dark' ? '2026-10-07T23:00:00' : '2026-10-07T12:00:00'));
}

function shooter(page, path, viewport, first = 0) {
  let n = first;
  return async (name, step) => {
    const label = `${String(++n).padStart(2, '0')}-${name}`;
    try {
      if (step) await step();
      await page.waitForTimeout(500);
      const dir = join(OUT, path, label);
      mkdirSync(dir, { recursive: true });
      await page.screenshot({ path: join(dir, `${viewport}-${THEME}.png`) });
    } catch (e) {
      mkdirSync(OUT, { recursive: true });
      appendFileSync(join(OUT, 'failed.txt'), `${path}/${label} ${viewport}-${THEME}: ${String(e.message).split('\n')[0]}\n`);
    }
  };
}

const attempt = async (page, step) => { try { await step(); } catch (e) { appendFileSync(join(OUT, 'failed.txt'), `step: ${String(e.message).split('\n')[0]}\n`); } };

const long = { title: 'A Rather Long Title For A Book That Goes On And On', author: 'Someone With A Rather Long Name' };

test.beforeEach(async ({ page }) => { await theme(page); });

test('first-run-library', async ({ page }, info) => {
  const shot = shooter(page, 'first-run-library', info.project.name);
  await page.route('https://www.gutenberg.org/**', route => route.fulfill({
    status: 200, headers: { 'Access-Control-Allow-Origin': '*' }, contentType: 'application/atom+xml',
    body: '<?xml version="1.0" encoding="UTF-8"?><feed xmlns="http://www.w3.org/2005/Atom"><id>urn:ux</id>' +
      '<title>Top 100 EBooks</title><updated>2026-10-01T00:00:00Z</updated>' +
      '<entry><title>Pride and Prejudice</title><id>a</id><author><name>Jane Austen</name></author><link rel="http://opds-spec.org/acquisition" href="/a.epub" type="application/epub+zip"/></entry>' +
      '<entry><title>Moby Dick; Or, The Whale</title><id>b</id><author><name>Herman Melville</name></author><link rel="http://opds-spec.org/acquisition" href="/b.epub" type="application/epub+zip"/></entry></feed>',
  }));
  await start(page);
  await shot('empty-library');
  await shot('import-picker-menu', async () => { await libraryMenu(page); });
  await page.keyboard.press('Escape');
  await shot('catalogues-list', async () => { await libraryMenu(page); await menuItem(page, 'Catalogues').click(); await expect(dialog(page, 'Catalogues')).toBeVisible(); });
  await shot('catalogue-browse', async () => {
    await dialog(page, 'Catalogues').getByRole('group', { name: 'Project Gutenberg' }).getByRole('button', { name: 'Project Gutenberg' }).click();
    await expect(page.getByRole('button', { name: 'Close catalogue' })).toBeVisible();
  });
  await attempt(page, async () => { await page.getByRole('button', { name: 'Close catalogue' }).click(); });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  const files = [
    epubFile({ ...long, coverImage: true, rawChapters: chapters(2) }),
    epubFile({ title: 'Short', author: 'S', rawChapters: chapters(2) }),
    epubFile({ title: 'Moby Dick', author: 'Herman Melville', coverImage: true, rawChapters: chapters(2) }),
    epubFile({ title: 'Pride and Prejudice', author: 'Jane Austen', rawChapters: chapters(2) }),
  ];
  await importFiles(page, files, 4);
  await shot('library-list');
  await shot('library-grid', async () => { await page.getByRole('group', { name: 'View' }).getByRole('button', { name: 'Grid' }).click(); });
  await attempt(page, async () => { await page.getByRole('group', { name: 'View' }).getByRole('button', { name: 'List' }).click(); });
  await shot('library-search', async () => { await page.getByRole('searchbox', { name: 'Search the library' }).fill('moby'); });
  await attempt(page, async () => { await page.getByRole('searchbox', { name: 'Search the library' }).fill(''); });
  await shot('book-menu', async () => { await bookMenu(page, 'Short'); });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  await shot('book-info', async () => { await bookMenu(page, 'Short'); await menuItem(page, 'Book info').click(); await expect(dialog(page, 'Book info')).toBeVisible(); });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  await shot('collections', async () => { await bookMenu(page, 'Short'); await menuItem(page, 'Collections').click(); await expect(dialog(page, 'Collections')).toBeVisible(); });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  await shot('library-menu', async () => { await libraryMenu(page); });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  await shot('duplicate-import', async () => { await importInput(page).setInputFiles([files[1]]); await expect(dialog(page, 'Already in library')).toBeVisible(); });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  await shot('bad-file-banner', async () => {
    await importInput(page).setInputFiles([rawFile('notes.epub', Buffer.from('this is not a zip file at all'))]);
    await expect(page.getByRole('alert')).toBeVisible();
  });
});

test('reading', async ({ page }, info) => {
  const shot = shooter(page, 'reading', info.project.name);
  const made = createStardict({ name: 'Pocket English', entries: [{ word: 'lorem', article: 'placeholder text' }] });
  await start(page);
  await attempt(page, async () => {
    await librarySettings(page);
    await settingsButton(page, 'Dictionaries ›').click();
    await page.getByLabel('Import dictionary').setInputFiles([rawFile('p.ifo', made.ifo), rawFile('p.idx', made.idx), rawFile('p.dict', made.dict)]);
    await expect(dialog(page, 'Dictionaries').getByRole('status')).toHaveText('Dictionary added.', { timeout: 30000 });
    await page.keyboard.press('Escape'); await page.keyboard.press('Escape');
    await expect(settingsScreen(page)).toBeHidden();
  });
  await readBook(page, {
    title: 'A Rather Long Title, Read', author: 'L',
    rawChapters: [...chapters(2), { body: '<h1>Part 3</h1><p>ephemeral claims<a epub:type="noteref" href="#n1">1</a>.</p><p><img src="images/map.png" alt="the map"/></p><aside epub:type="footnote" id="n1"><p>The note.</p></aside>' }],
    extraImages: [{ name: 'images/map.png', data: solidPng(240, 240) }],
  });
  await shot('reading-bars-down');
  await shot('reading-bars-up', async () => { await showChrome(page); });
  await shot('page-turn-mid-animation', async () => {
    await page.keyboard.press('ArrowRight');
    await page.waitForTimeout(120);
  });
  await shot('contents', async () => { await page.waitForTimeout(400); await clickControl(page, 'Contents'); await expect(dialog(page, 'Contents')).toBeVisible(); });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  await shot('search-in-book', async () => { await showChrome(page); await topBar(page).getByRole('button', { name: 'Search in book' }).click(); await expect(dialog(page, 'Search in book')).toBeVisible(); });
  await attempt(page, async () => { await dialog(page, 'Search in book').getByRole('searchbox', { name: 'Search in book' }).fill('ipsum'); await page.keyboard.press('Enter'); });
  await shot('search-results');
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  await shot('selection-toolbar', async () => { await selectText(page, 0, 9); await expect(page.getByRole('toolbar', { name: 'Selection' })).toBeVisible(); });
  await shot('highlight-made', async () => { await selectionButton(page, 'Highlight').click(); await page.waitForTimeout(300); });
  await shot('bookmark', async () => { await showChrome(page); await page.getByRole('button', { name: 'Bookmark this page' }).click(); });
  await shot('annotations', async () => { await clickControl(page, 'Annotations'); await expect(dialog(page, 'Annotations')).toBeVisible(); });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  await shot('look-up', async () => {
    await selectText(page, 0, 4);
    await page.getByRole('toolbar', { name: 'Selection' }).getByRole('button', { name: 'Look up', exact: true }).click();
    await expect(dialog(page, 'Dictionary')).toBeVisible();
  });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  await attempt(page, async () => {
    for (let turn = 0; turn < 80; turn++) {
      const there = await page.evaluate(() => [...document.querySelectorAll('[role=document] img[alt="the map"]')].some(i => { const r = i.getBoundingClientRect(); return r.width > 0 && r.left >= 0 && r.right <= innerWidth && r.top >= 0 && r.bottom <= innerHeight; }));
      if (there) break;
      await page.keyboard.press('ArrowRight'); await page.waitForTimeout(350);
    }
  });
  await shot('footnote', async () => { await bookPage(page).getByRole('link', { name: '1', exact: true }).click(); await expect(dialog(page, 'Footnote')).toBeVisible(); });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  await shot('picture-viewer', async () => { await bookPage(page).getByRole('img', { name: 'the map' }).click(); await expect(dialog(page, 'Image')).toBeVisible(); });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  await attempt(page, async () => { await toLibrary(page); });
  // right to left, vertical, fixed layout
  await readBook(page, { title: 'Hebrew', author: 'R', language: 'he', rtl: true, rawChapters: [{ body: '<h1>פרק 1</h1>' + '<p>' + 'זה טקסט לדוגמה בעברית כדי לראות את העמוד. '.repeat(40) + '</p>'.repeat(1) }, { body: '<h1>פרק 2</h1><p>' + 'טקסט נוסף. '.repeat(100) + '</p>' }] });
  await shot('rtl-reading-bars-down');
  await shot('rtl-reading-bars-up', async () => { await showChrome(page); });
  await attempt(page, async () => { await toLibrary(page); });
  await readBook(page, { title: '縦書き', author: '著者', language: 'ja', rtl: true, rawChapters: japaneseChapters(2, 40) });
  await shot('vertical-reading-bars-down');
  await shot('vertical-reading-bars-up', async () => { await showChrome(page); });
  await attempt(page, async () => { await toLibrary(page); });
  await attempt(page, async () => { await readFixed(page, fixedLayoutBook('Picture Book', 4, { spread: 'auto' })); });
  await shot('fixed-layout');
});

test('settings-sync', async ({ page }, info) => {
  const shot = shooter(page, 'settings-sync', info.project.name);
  await start(page);
  await readBook(page, { title: 'Settings Book', author: 'S', rawChapters: chapters(3) });
  for (const tab of ['Look', 'Page', 'Turning', 'Read aloud']) {
    await shot(`reading-settings-${tab.toLowerCase().replace(' ', '-')}`, async () => { await openReadingSettings(page, tab); });
  }
  await attempt(page, async () => { await page.keyboard.press('Escape'); await toLibrary(page); });
  await shot('statistics', async () => { await libraryMenu(page); await menuItem(page, 'Reading statistics').click(); await expect(dialog(page, 'Reading statistics')).toBeVisible(); });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  await shot('about', async () => { await libraryMenu(page); await menuItem(page, 'About Quire').click(); await expect(dialog(page, 'About Quire')).toBeVisible(); });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  await shot('settings', async () => { await librarySettings(page); });
  await shot('settings-dictionaries', async () => { await settingsButton(page, 'Dictionaries ›').click(); await expect(dialog(page, 'Dictionaries')).toBeVisible(); });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  await shot('settings-sync', async () => { await settingsButton(page, 'Sync ›').click(); await expect(dialog(page, 'Sync')).toBeVisible(); });
  await attempt(page, async () => {
    const sync = dialog(page, 'Sync');
    const rows = await sync.getByRole('group', { name: 'Sync with' }).getByRole('button').allTextContents();
    for (const row of rows) {
      await shot(`sync-step-${row.replace(/ ›/, '').toLowerCase().replace(/[^a-z]+/g, '-')}`, async () => {
        await sync.getByRole('button', { name: row, exact: true }).click();
        await expect(sync.getByRole('button', { name: 'Cancel', exact: true })).toBeVisible();
      });
      await page.keyboard.press('Escape');
    }
  });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  await shot('backup-restored', async () => {
    const download = page.waitForEvent('download');
    await settingsButton(page, 'Export backup').click();
    const path = await (await download).path();
    await page.getByLabel('Restore backup').setInputFiles([path]);
    await expect(dialog(page, 'Backup restored')).toBeVisible();
  });
});

test('trash-errors', async ({ page }, info) => {
  const shot = shooter(page, 'trash-errors', info.project.name);
  await start(page);
  await importFiles(page, [
    epubFile({ title: 'Keep Me', author: 'K', rawChapters: chapters(2) }),
    epubFile({ title: 'Remove Me', author: 'R', rawChapters: chapters(2) }),
  ], 2);
  await shot('move-to-trash-undo-toast', async () => { await bookMenu(page, 'Remove Me'); await menuItem(page, 'Move to Trash').click(); await expect(page.getByRole('button', { name: 'Undo', exact: true })).toBeVisible(); });
  await attempt(page, async () => { await page.waitForTimeout(6000); });
  await shot('trash-shelf', async () => { const shelf = page.getByRole('button', { name: /^(Library|Hidden|Archived|Trash)$/ }); for (let i = 0; i < 3; i++) await shelf.click(); });
  await shot('trash-book-menu', async () => { await bookMenu(page, 'Remove Me'); });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  await shot('empty-trash-dialog', async () => { await libraryMenu(page); await menuItem(page, 'Empty Trash').click(); await expect(dialog(page, 'Empty the Trash?')).toBeVisible(); });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
  await shot('factory-reset', async () => { await librarySettings(page); await settingsButton(page, 'Factory reset').click(); });
  await attempt(page, async () => { await page.keyboard.press('Escape'); });
});

test('errors', async ({ page }, info) => {
  const shot = shooter(page, 'trash-errors', info.project.name, 20);
  await start(page);
  await readBook(page, {
    title: 'Damaged Book', author: 'Notice Tests',
    rawChapters: [{ body: '<h1>Part 1</h1><p>Para 1.0 short</p>' }, ...chapters(3).slice(1)], damagedChapters: [2],
  });
  await shot('chapter-cannot-be-read-banner', async () => { await page.keyboard.press('ArrowRight'); await expect(page.getByRole('alert')).toBeVisible(); });
  await attempt(page, async () => { await page.getByRole('alert').getByRole('button', { name: 'Dismiss' }).click(); await toLibrary(page); });
  await attempt(page, async () => {
    await page.evaluate(() => localStorage.setItem('failReads', 'lib'));
    await page.addInitScript(() => {
      const failing = key => localStorage.getItem('failReads') === 'lib' && key === 'lib';
      const get = IDBObjectStore.prototype.get;
      IDBObjectStore.prototype.get = function (key) {
        if (!failing(key)) return get.call(this, key);
        const request = { result: undefined, error: new DOMException('read failed', 'UnknownError') };
        setTimeout(() => { if (request.onerror) request.onerror(new Event('error')); });
        return request;
      };
    });
    await page.reload();
  });
  await shot('library-cannot-be-read-banner', async () => { await expect(page.getByRole('alert')).toBeVisible(); });
});
