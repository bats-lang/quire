// OPDS catalogues: the library menu's Catalogues (Project Gutenberg's
// at first, others added by name and URL, removed with Undo, kept
// across reloads and listed in the backup), and one browsed: its
// navigation and acquisition pages (OPDS 1.2 Atom and OPDS 2 JSON),
// Next and Previous, Back, its search, and Get, which imports a book,
// or where a browser may not read it gives way to a download link.
//
// Every page, cover and book is served here (page.route) from the made
// up hosts catalogue.test and elsewhere.test; any other request off
// the app's own server is aborted, so nothing reaches the network.

import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { readFileSync } from 'node:fs';
import { start, libraryMenu, menuItem, dialog, reload, cards, card, librarySettings, settingsButton } from './helpers.js';
import { createEpub, TINY_PNG } from './create-epub.js';

const HOST = 'https://catalogue.test';
const ROOT = `${HOST}/opds/root.xml`;

const atom = (title, body) => `<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog">
  <id>urn:test</id>
  <title>${title}</title>
  <updated>2026-10-01T00:00:00Z</updated>
${body}
</feed>`;

const NAVIGATION = 'application/atom+xml;profile=opds-catalog;kind=navigation';
const ACQUISITION = 'application/atom+xml;profile=opds-catalog;kind=acquisition';

// a navigation feed: a page of links, a relative one, one rooted at the
// host and one to an OPDS 2 page, and its search's description
const root = atom('Test Catalogue', `
  <link rel="self" href="root.xml" type="${NAVIGATION}"/>
  <link rel="search" href="search.xml" type="application/opensearchdescription+xml"/>
  <entry><title>Fiction</title><id>fiction</id>
    <link rel="subsection" href="fiction.xml" type="${ACQUISITION}"/></entry>
  <entry><title>Novels &amp; More</title><id>novels</id>
    <link rel="subsection" href="/opds2/novels.json" type="application/opds+json"/></entry>`);

// an acquisition feed: a book with an EPUB and an EPUB 3 (the EPUB 3 is
// got), its thumbnail ("..", resolved), one served without CORS, and
// the next page
const fiction = atom('Fiction', `
  <link rel="next" href="fiction-2.xml" type="${ACQUISITION}"/>
  <entry><title>First Book</title><id>first</id>
    <author><name>Ann Author</name></author>
    <link rel="http://opds-spec.org/image/thumbnail" href="../covers/first.png" type="image/png"/>
    <link rel="http://opds-spec.org/acquisition/open-access" href="/books/first.epub" type="application/epub+zip"/>
    <link rel="http://opds-spec.org/acquisition/open-access" href="/books/first.epub3" type="application/epub+zip"/>
  </entry>
  <entry><title>Faraway Book</title><id>faraway</id>
    <author><name>Bea Blocked</name></author>
    <link rel="http://opds-spec.org/acquisition" href="https://elsewhere.test/faraway.epub" type="application/epub+zip"/>
  </entry>`);

const fictionTwo = atom('Fiction, page 2', `
  <link rel="previous" href="fiction.xml" type="${ACQUISITION}"/>
  <entry><title>Second Page Book</title><id>second</id>
    <link rel="http://opds-spec.org/acquisition" href="/books/second.epub" type="application/epub+zip"/>
  </entry>`);

const description = `<?xml version="1.0" encoding="UTF-8"?>
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
  <ShortName>Test</ShortName>
  <Url type="text/html" template="${HOST}/html?q={searchTerms}"/>
  <Url type="application/atom+xml;profile=opds-catalog" template="${HOST}/opds/search?q={searchTerms}&amp;page={startPage?}"/>
</OpenSearchDescription>`;

const found = atom('Results', `
  <entry><title>Dragon Book</title><id>dragon</id>
    <link rel="http://opds-spec.org/acquisition" href="/books/dragon.epub" type="application/epub+zip"/>
  </entry>`);

// an OPDS 2 page: a publication (its author an object, its cover an
// image) and a navigation link back
const novels = JSON.stringify({
  metadata: { title: 'Novels' },
  links: [{ rel: 'self', href: '/opds2/novels.json', type: 'application/opds+json' }],
  navigation: [{ title: 'Back to the start', href: '../opds/root.xml', type: 'application/atom+xml' }],
  publications: [{
    metadata: { title: 'Json Novel', author: { name: 'Jay Son' } },
    links: [{ rel: 'http://opds-spec.org/acquisition', href: '/books/json.epub', type: 'application/epub+zip' }],
    images: [{ href: '/covers/json.png', type: 'image/png' }],
  }],
});

const epubs = {
  '/books/first.epub3': createEpub({ title: 'First Book', author: 'Ann Author' }),
  '/books/first.epub': createEpub({ title: 'First Book (old EPUB)', author: 'Ann Author' }),
  '/books/second.epub': createEpub({ title: 'Second Page Book' }),
  '/books/dragon.epub': createEpub({ title: 'Dragon Book' }),
  '/books/json.epub': createEpub({ title: 'Json Novel', author: 'Jay Son' }),
};

const CORS = { 'Access-Control-Allow-Origin': '*' };

/** Serves the catalogue; returns the paths asked for, in order */
async function serve(page) {
  const asked = [];
  // nothing reaches the network: whatever is not served below is aborted
  await page.route(url => url.hostname !== 'localhost', route => route.abort());
  await page.route(`${HOST}/**`, route => {
    const url = new URL(route.request().url());
    asked.push(url.pathname + url.search);
    const xml = body => route.fulfill({ status: 200, headers: CORS, contentType: 'application/atom+xml', body });
    switch (url.pathname) {
      case '/opds/root.xml': return xml(root);
      case '/opds/fiction.xml': return xml(fiction);
      case '/opds/fiction-2.xml': return xml(fictionTwo);
      case '/opds/search.xml': return route.fulfill({ status: 200, headers: CORS, contentType: 'application/opensearchdescription+xml', body: description });
      case '/opds/search': return xml(url.searchParams.get('q') === 'red dragons' ? found : atom('Results', ''));
      case '/opds2/novels.json': return route.fulfill({ status: 200, headers: CORS, contentType: 'application/opds+json', body: novels });
      case '/opds/missing.xml': return route.fulfill({ status: 404, headers: CORS, body: 'Not Found' });
      case '/opds/private.xml': return route.fulfill({ status: 401, headers: CORS, body: 'Sign in' });
      case '/opds/page.html': return route.fulfill({ status: 200, headers: CORS, contentType: 'text/html', body: '<!doctype html><html><body><p>Hello</p></body></html>' });
      // a catalogue whose pages a browser may not read (its server sends
      // no CORS header): the fetch fails, as a blocked one does
      case '/opds/closed.xml': return route.abort('accessdenied');
    }
    if (url.pathname.startsWith('/covers/')) return route.fulfill({ status: 200, headers: CORS, contentType: 'image/png', body: TINY_PNG });
    if (epubs[url.pathname]) return route.fulfill({ status: 200, headers: CORS, contentType: 'application/epub+zip', body: epubs[url.pathname] });
    return route.fulfill({ status: 404, headers: CORS, body: '' });
  });
  return asked;
}

const catalogues = page => dialog(page, 'Catalogues');
/** The catalogue browsed (named by its page's title) */
const browser = page => page.getByRole('dialog').filter({ has: page.getByRole('button', { name: 'Close catalogue' }) });
const status = page => browser(page).getByRole('status');
const entries = page => browser(page).getByRole('region', { name: 'Entries' });
const book = (page, title) => entries(page).getByRole('group', { name: title });

async function openCatalogues(page) {
  await libraryMenu(page);
  await menuItem(page, 'Catalogues').click();
  await expect(catalogues(page)).toBeVisible();
}

/** Adds the catalogue name at url, from the library */
async function addCatalogue(page, name, url) {
  await openCatalogues(page);
  await catalogues(page).getByRole('textbox', { name: 'Catalogue name' }).fill(name);
  await catalogues(page).getByRole('textbox', { name: 'Catalogue URL' }).fill(url);
  await catalogues(page).getByRole('button', { name: 'Add catalogue' }).click();
  await expect(catalogues(page).getByRole('status')).toHaveText('Catalogue added.');
  await expect(catalogues(page).getByRole('group', { name })).toBeVisible();
}

/** Opens the catalogue name from the Catalogues panel, and waits for its page */
async function browse(page, name, title) {
  await catalogues(page).getByRole('group', { name }).getByRole('button', { name }).click();
  await expect(catalogues(page)).toBeHidden();
  await expect(browser(page)).toBeVisible();
  if (title) await expect(browser(page)).toHaveAccessibleName(title);
}

const audit = async page => {
  const r = await new AxeBuilder({ page }).analyze();
  return r.violations.map(v => `${v.id}: ${v.nodes.map(n => n.target.join(' ')).join(', ')}`);
};

test('the catalogues: Project Gutenberg at first, one added, removed with Undo, kept across reloads', async ({ page }) => {
  await serve(page);
  const errors = await start(page);
  await openCatalogues(page);
  await expect(catalogues(page).getByRole('group', { name: 'Project Gutenberg' })).toBeVisible();
  expect(await audit(page)).toEqual([]);
  // an address that is not a web one is refused
  await catalogues(page).getByRole('textbox', { name: 'Catalogue name' }).fill('Nowhere');
  await catalogues(page).getByRole('textbox', { name: 'Catalogue URL' }).fill('ftp://catalogue.test/');
  await catalogues(page).getByRole('button', { name: 'Add catalogue' }).click();
  await expect(catalogues(page).getByRole('status')).toContainText('https://');
  await expect(catalogues(page).getByRole('group', { name: 'Nowhere' })).toHaveCount(0);
  await page.keyboard.press('Escape');

  await addCatalogue(page, 'Test Catalogue', ROOT);
  // the fields are emptied for the next one
  await expect(catalogues(page).getByRole('textbox', { name: 'Catalogue name' })).toHaveValue('');
  await reload(page);
  await openCatalogues(page);
  const row = catalogues(page).getByRole('group', { name: 'Test Catalogue' });
  await expect(row).toBeVisible();
  await expect(catalogues(page).getByRole('group', { name: 'Project Gutenberg' })).toBeVisible();

  // removed, and put back by Undo
  await row.getByRole('button', { name: 'Remove' }).click();
  await expect(row).toBeHidden();
  const toast = page.getByRole('status').filter({ hasText: 'Catalogue removed' });
  await expect(toast).toBeVisible();
  await toast.getByRole('button', { name: 'Undo' }).click();
  await expect(row).toBeVisible();
  await reload(page);
  await openCatalogues(page);
  await expect(row).toBeVisible();

  // removed, and the toast left to go: gone for good, as Project
  // Gutenberg's is once it is removed
  await row.getByRole('button', { name: 'Remove' }).click();
  await catalogues(page).getByRole('group', { name: 'Project Gutenberg' }).getByRole('button', { name: 'Remove' }).click();
  await expect(catalogues(page).getByText('No catalogues yet')).toBeVisible();
  await expect(toast).toBeHidden({ timeout: 15000 });
  await reload(page);
  await openCatalogues(page);
  await expect(catalogues(page).getByText('No catalogues yet')).toBeVisible();
  expect(errors).toEqual([]);
});

test('a catalogue is browsed: a navigation page, an acquisition page and its next, and Back', async ({ page }) => {
  const asked = await serve(page);
  const errors = await start(page);
  await addCatalogue(page, 'Test Catalogue', ROOT);
  await browse(page, 'Test Catalogue', 'Test Catalogue');
  await expect(entries(page).getByRole('button', { name: 'Fiction' })).toBeVisible();
  // its title's reference is decoded
  await expect(entries(page).getByRole('button', { name: 'Novels & More' })).toBeVisible();
  expect(await audit(page)).toEqual([]);

  // a relative link, resolved against the page's address
  await entries(page).getByRole('button', { name: 'Fiction' }).click();
  await expect(browser(page)).toHaveAccessibleName('Fiction');
  expect(asked).toContain('/opds/fiction.xml');
  const first = book(page, 'First Book');
  await expect(first).toContainText('Ann Author');
  await expect(first.getByRole('button', { name: 'Get' })).toBeVisible();
  await expect(first.locator('img')).toHaveAttribute('src', `${HOST}/covers/first.png`);
  await expect(book(page, 'Faraway Book')).toBeVisible();
  expect(await audit(page)).toEqual([]);

  // the next page, and back with Previous
  await expect(browser(page).getByRole('button', { name: 'Previous' })).toBeHidden();
  await browser(page).getByRole('button', { name: 'Next' }).click();
  await expect(browser(page)).toHaveAccessibleName('Fiction, page 2');
  await expect(book(page, 'Second Page Book')).toBeVisible();
  await expect(browser(page).getByRole('button', { name: 'Next' })).toBeHidden();
  await browser(page).getByRole('button', { name: 'Previous' }).click();
  await expect(browser(page)).toHaveAccessibleName('Fiction');

  // Back goes back through the pages, and from the first to the list
  await browser(page).getByRole('button', { name: 'Back', exact: true }).click();
  await expect(browser(page)).toHaveAccessibleName('Fiction, page 2');
  await browser(page).getByRole('button', { name: 'Back', exact: true }).click();
  await expect(browser(page)).toHaveAccessibleName('Fiction');
  await browser(page).getByRole('button', { name: 'Back', exact: true }).click();
  await expect(browser(page)).toHaveAccessibleName('Test Catalogue');
  await browser(page).getByRole('button', { name: 'Back', exact: true }).click();
  await expect(browser(page)).toBeHidden();
  await expect(catalogues(page)).toBeVisible();

  // Close leaves the catalogue for the library
  await browse(page, 'Test Catalogue', 'Test Catalogue');
  await browser(page).getByRole('button', { name: 'Close catalogue' }).click();
  await expect(browser(page)).toBeHidden();
  expect(errors).toEqual([]);
});

test('an OPDS 2 page shows its publications and navigation, and Get imports from it', async ({ page }) => {
  await serve(page);
  await start(page);
  await addCatalogue(page, 'Test Catalogue', ROOT);
  await browse(page, 'Test Catalogue', 'Test Catalogue');
  await entries(page).getByRole('button', { name: 'Novels & More' }).click();
  await expect(browser(page)).toHaveAccessibleName('Novels');
  const novel = book(page, 'Json Novel');
  await expect(novel).toContainText('Jay Son');
  await expect(novel.locator('img')).toHaveAttribute('src', `${HOST}/covers/json.png`);
  await novel.getByRole('button', { name: 'Get' }).click();
  await expect(status(page)).toHaveText('Added to your library.', { timeout: 30000 });
  await expect(card(page, 'Json Novel')).toHaveCount(1);
  // its navigation link, "../opds/root.xml" from /opds2/
  await entries(page).getByRole('button', { name: 'Back to the start' }).click();
  await expect(browser(page)).toHaveAccessibleName('Test Catalogue');
});

test('a catalogue is searched with the template its OpenSearch description gives', async ({ page }) => {
  const asked = await serve(page);
  await start(page);
  await addCatalogue(page, 'Test Catalogue', ROOT);
  await browse(page, 'Test Catalogue', 'Test Catalogue');
  const field = browser(page).getByRole('searchbox', { name: 'Search the catalogue' });
  await expect(field).toBeVisible();
  await field.fill('red dragons');
  await field.press('Enter');
  await expect(book(page, 'Dragon Book')).toBeVisible();
  // the Atom template, its query encoded and its optional parameter left out
  expect(asked).toContain('/opds/search?q=red%20dragons&page=');
  // Back returns to the page searched from
  await browser(page).getByRole('button', { name: 'Back', exact: true }).click();
  await expect(browser(page)).toHaveAccessibleName('Test Catalogue');
  // the search button does the same
  await field.fill('nothing here');
  await browser(page).getByRole('button', { name: 'Search', exact: true }).click();
  await expect(status(page)).toHaveText('Nothing here.');
});

test('Get imports a book (its EPUB 3), and Get again finds it already in the library', async ({ page }) => {
  const asked = await serve(page);
  const errors = await start(page);
  await addCatalogue(page, 'Test Catalogue', ROOT);
  await browse(page, 'Test Catalogue', 'Test Catalogue');
  await entries(page).getByRole('button', { name: 'Fiction' }).click();
  const first = book(page, 'First Book');
  await first.getByRole('button', { name: 'Get' }).click();
  await expect(status(page)).toHaveText('Added to your library.', { timeout: 30000 });
  expect(asked).toContain('/books/first.epub3');
  expect(asked).not.toContain('/books/first.epub');
  await expect(cards(page)).toHaveCount(1);
  await expect(card(page, 'First Book')).toContainText('Ann Author');

  // the same book again: the import asks, as for a file picked twice
  await first.getByRole('button', { name: 'Get' }).click();
  const ask = dialog(page, 'Already in library');
  await expect(ask).toBeVisible({ timeout: 30000 });
  await expect(ask).toContainText('First Book is already in your library.');
  await ask.getByRole('button', { name: 'Skip' }).click();
  await expect(ask).toBeHidden();
  await expect(cards(page)).toHaveCount(1);
  expect(errors).toEqual([]);
});

test('a book a browser may not read is offered as a download, to import then', async ({ page }) => {
  await serve(page);
  await start(page);
  await addCatalogue(page, 'Test Catalogue', ROOT);
  await browse(page, 'Test Catalogue', 'Test Catalogue');
  await entries(page).getByRole('button', { name: 'Fiction' }).click();
  const faraway = book(page, 'Faraway Book');
  await expect(faraway.getByRole('link', { name: 'Download' })).toBeHidden();
  await faraway.getByRole('button', { name: 'Get' }).click();
  const download = faraway.getByRole('link', { name: 'Download' });
  await expect(download).toBeVisible();
  await expect(faraway.getByRole('button', { name: 'Get' })).toBeHidden();
  await expect(faraway).toContainText('then import it');
  await expect(download).toHaveAttribute('href', 'https://elsewhere.test/faraway.epub');
  await expect(download).toHaveAttribute('download', '');
  await expect(download).toHaveAttribute('rel', /noopener/);
  await expect(cards(page)).toHaveCount(0);
  expect(await audit(page)).toEqual([]);
});

test('a page that cannot be read says why', async ({ page }) => {
  await serve(page);
  await start(page);
  const cases = [
    ['Missing', `${HOST}/opds/missing.xml`, 'Not found.'],
    ['Private', `${HOST}/opds/private.xml`, 'Needs a sign-in.'],
    ['Web page', `${HOST}/opds/page.html`, "This isn't a catalogue."],
    ['Closed', `${HOST}/opds/closed.xml`, "This catalogue doesn't let a browser read it."],
  ];
  for (const [name, url] of cases) {
    await addCatalogue(page, name, url);
    await page.keyboard.press('Escape');
  }
  for (const [name, , message] of cases) {
    await openCatalogues(page);
    await browse(page, name);
    await expect(status(page)).toHaveText(message);
    await expect(entries(page).getByRole('button')).toHaveCount(0);
    await browser(page).getByRole('button', { name: 'Close catalogue' }).click();
  }
});

test('the backup lists the catalogues, by name and URL', async ({ page }) => {
  await serve(page);
  await start(page);
  await addCatalogue(page, 'Test Catalogue', ROOT);
  await page.keyboard.press('Escape');
  await librarySettings(page);
  const downloading = page.waitForEvent('download');
  await settingsButton(page, 'Export backup').click();
  const backup = JSON.parse(readFileSync(await (await downloading).path(), 'utf8'));
  expect(backup.catalogues).toEqual([
    { name: 'Project Gutenberg', url: 'https://www.gutenberg.org/ebooks/search.opds/' },
    { name: 'Test Catalogue', url: ROOT },
  ]);
});
