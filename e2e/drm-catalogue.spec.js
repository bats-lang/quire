// A book of a catalogue whose only acquisition link is a licence of a
// DRM Quire has no client for (Adobe ADEPT's
// application/vnd.adobe.adept+xml, Readium LCP's
// application/vnd.readium.lcp.license.v1.0+json) says so in place of
// Get, and nothing of it is downloaded (quire#427). A book that also
// has an EPUB is got as ever. Every page is served from a made up host.

import { test, expect } from './fixtures.js';
import AxeBuilder from '@axe-core/playwright';
import { start, libraryMenu, menuItem, dialog, cards } from './helpers.js';
import { createEpub } from './create-epub.js';

const HOST = 'https://drm-catalogue.test';
const ROOT = `${HOST}/opds/root.xml`;
const CORS = { 'Access-Control-Allow-Origin': '*' };

const ADEPT = 'application/vnd.adobe.adept+xml';
const LCP = 'application/vnd.readium.lcp.license.v1.0+json';

const atom = (title, body) => `<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog">
  <id>urn:test</id>
  <title>${title}</title>
  <updated>2026-10-01T00:00:00Z</updated>
${body}
</feed>`;

const ACQUISITION = 'application/atom+xml;profile=opds-catalog;kind=acquisition';

const root = atom('Protected Catalogue', `
  <entry><title>Protected Shelf</title><id>shelf</id>
    <link rel="subsection" href="shelf.xml" type="${ACQUISITION}"/></entry>
  <entry><title>Protected Json Shelf</title><id>json-shelf</id>
    <link rel="subsection" href="/opds2/shelf.json" type="application/opds+json"/></entry>`);

const shelf = atom('Protected Shelf', `
  <entry><title>Adept Loan</title><id>adept</id>
    <author><name>Ann Adept</name></author>
    <link rel="http://opds-spec.org/acquisition/borrow" href="/books/adept.acsm" type="${ADEPT}"/>
  </entry>
  <entry><title>Lcp Loan</title><id>lcp</id>
    <link rel="http://opds-spec.org/acquisition/borrow" href="/books/lcp.lcpl" type="${LCP}"/>
  </entry>
  <entry><title>Lcp Or Free</title><id>both</id>
    <link rel="http://opds-spec.org/acquisition/borrow" href="/books/both.lcpl" type="${LCP}"/>
    <link rel="http://opds-spec.org/acquisition/open-access" href="/books/both.epub" type="application/epub+zip"/>
  </entry>
  <entry><title>Free Book</title><id>free</id>
    <link rel="http://opds-spec.org/acquisition/open-access" href="/books/free.epub" type="application/epub+zip"/>
  </entry>`);

const jsonShelf = JSON.stringify({
  metadata: { title: 'Protected Json Shelf' },
  links: [{ rel: 'self', href: '/opds2/shelf.json', type: 'application/opds+json' }],
  publications: [{
    metadata: { title: 'Json Lcp Loan', author: { name: 'Jay Son' } },
    links: [{ rel: 'http://opds-spec.org/acquisition/borrow', href: '/books/json.lcpl', type: LCP }],
  }, {
    metadata: { title: 'Json Adept Loan' },
    links: [{ rel: 'http://opds-spec.org/acquisition/borrow', href: '/books/json.acsm', type: ADEPT }],
  }, {
    metadata: { title: 'Json Free Book' },
    links: [{ rel: 'http://opds-spec.org/acquisition', href: '/books/free.epub', type: 'application/epub+zip' }],
  }],
});

/** Serves the catalogue; returns the paths asked for, in order */
async function serve(page) {
  const asked = [];
  await page.route(url => url.hostname !== 'localhost', route => route.abort());
  await page.route(`${HOST}/**`, route => {
    const url = new URL(route.request().url());
    asked.push(url.pathname);
    const xml = body => route.fulfill({ status: 200, headers: CORS, contentType: 'application/atom+xml', body });
    switch (url.pathname) {
      case '/opds/root.xml': return xml(root);
      case '/opds/shelf.xml': return xml(shelf);
      case '/opds2/shelf.json': return route.fulfill({ status: 200, headers: CORS, contentType: 'application/opds+json', body: jsonShelf });
      case '/books/free.epub': return route.fulfill({ status: 200, headers: CORS, contentType: 'application/epub+zip', body: createEpub({ title: 'Free Book' }) });
      case '/books/both.epub': return route.fulfill({ status: 200, headers: CORS, contentType: 'application/epub+zip', body: createEpub({ title: 'Lcp Or Free' }) });
    }
    return route.fulfill({ status: 404, headers: CORS, body: '' });
  });
  return asked;
}

const catalogues = page => dialog(page, 'Catalogues');
const browser = page => page.getByRole('dialog').filter({ has: page.getByRole('button', { name: 'Close catalogue' }) });
const entries = page => browser(page).getByRole('region', { name: 'Entries' });
const book = (page, title) => entries(page).getByRole('group', { name: title });

async function browse(page) {
  await libraryMenu(page);
  await menuItem(page, 'Catalogues').click();
  await catalogues(page).getByRole('textbox', { name: 'Catalogue name' }).fill('Protected Catalogue');
  await catalogues(page).getByRole('textbox', { name: 'Catalogue URL' }).fill(ROOT);
  await catalogues(page).getByRole('button', { name: 'Add catalogue' }).click();
  await catalogues(page).getByRole('group', { name: 'Protected Catalogue' }).getByRole('button', { name: 'Protected Catalogue' }).click();
  await expect(browser(page)).toHaveAccessibleName('Protected Catalogue');
}

const audit = async page => {
  const r = await new AxeBuilder({ page }).analyze();
  return r.violations.map(v => `${v.id}: ${v.nodes.map(n => n.target.join(' ')).join(', ')}`);
};

test('a book only an ADEPT or LCP licence gets says so before downloading, with no Get', async ({ page }) => {
  const asked = await serve(page);
  const errors = await start(page);
  await browse(page);
  await entries(page).getByRole('button', { name: 'Protected Shelf', exact: true }).click();
  await expect(browser(page)).toHaveAccessibleName('Protected Shelf');

  const adept = book(page, 'Adept Loan');
  await expect(adept).toContainText('Ann Adept');
  await expect(adept).toContainText('Protected by Adobe DRM: Quire cannot open it, so it cannot be got here');
  await expect(adept.getByRole('button', { name: 'Get' })).toHaveCount(0);
  await expect(adept.getByRole('link', { name: 'Download' })).toHaveCount(0);

  const lcp = book(page, 'Lcp Loan');
  await expect(lcp).toContainText('Protected by Readium LCP: Quire cannot open it, so it cannot be got here');
  await expect(lcp.getByRole('button', { name: 'Get' })).toHaveCount(0);

  // an EPUB beside the licence is got as ever
  const both = book(page, 'Lcp Or Free');
  await expect(both.getByRole('button', { name: 'Get' })).toBeVisible();
  await expect(both).not.toContainText('Protected by');
  const free = book(page, 'Free Book');
  await expect(free.getByRole('button', { name: 'Get' })).toBeVisible();
  await expect(free).not.toContainText('Protected by');
  expect(await audit(page)).toEqual([]);

  await both.getByRole('button', { name: 'Get' }).click();
  await expect(cards(page)).toHaveCount(1);
  // nothing was fetched of a licence
  expect(asked.filter(path => /\.(acsm|lcpl)$/.test(path))).toEqual([]);
  expect(errors).toEqual([]);
});

test('an OPDS 2 publication whose only link is an LCP or ADEPT licence says so, with no Get', async ({ page }) => {
  const asked = await serve(page);
  const errors = await start(page);
  await browse(page);
  await entries(page).getByRole('button', { name: 'Protected Json Shelf' }).click();
  await expect(browser(page)).toHaveAccessibleName('Protected Json Shelf');
  const lcp = book(page, 'Json Lcp Loan');
  await expect(lcp).toContainText('Protected by Readium LCP');
  await expect(lcp.getByRole('button', { name: 'Get' })).toHaveCount(0);
  const adept = book(page, 'Json Adept Loan');
  await expect(adept).toContainText('Protected by Adobe DRM');
  await expect(adept.getByRole('button', { name: 'Get' })).toHaveCount(0);
  await expect(book(page, 'Json Free Book').getByRole('button', { name: 'Get' })).toBeVisible();
  expect(await audit(page)).toEqual([]);
  expect(asked.filter(path => /\.(acsm|lcpl)$/.test(path))).toEqual([]);
  expect(errors).toEqual([]);
});
