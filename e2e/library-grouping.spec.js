// The library's two kinds of control (quire#861): the status filters, one
// segmented row, and the collection, one button that opens a menu. Every
// chip and button is as tall as the others, one gap lies between
// neighbours (across a line and from line to line), every line starts at
// the search field's left edge, and no group of controls ends a wrapped
// line in one lone button. The configuration runs this file in every
// project (the portrait and the landscape of each are played here by
// turning the window), at the default font scale and at 200% (#705). The
// engine scales text by a percentage in a mobile viewport only
// (font-scale.spec.js), so the 200% tests ask for one (isMobile) in every
// project, the android project's own included; the test checks that the
// scale reached the page.

import { test, expect } from './fixtures.js';
import { start, epubFile, importFiles, bookMenu, menuItem, dialog, cards, collectionButton, collectionMenu, showCollection } from './helpers.js';
import { scaledBy } from './font-scale.js';

// forty bytes, the longest a collection's name can be (COLL_NAME)
const LONG_NAME = 'A long name is cut with an ellipsis, not';

/** Makes a collection from a book's menu, with the book in it */
async function makeCollection(page, book, name) {
  await bookMenu(page, book);
  await menuItem(page, 'Collections').click();
  const panel = dialog(page, 'Collections');
  await panel.getByRole('button', { name: 'New collection' }).click();
  const field = dialog(page, 'New collection').getByRole('textbox', { name: 'Name' });
  await field.fill(name);
  await field.press('Enter');
  await panel.getByRole('button', { name: 'Done' }).click();
  await expect(panel).toBeHidden();
}

/** The library with three collections, the long one shown */
async function libraryWithCollections(page) {
  await start(page);
  await importFiles(page, [
    epubFile({ title: 'First Book', author: 'A' }),
    epubFile({ title: 'Second Book', author: 'B' }),
  ], 2);
  await makeCollection(page, 'First Book', 'Amber');
  await makeCollection(page, 'Second Book', 'To read');
  await makeCollection(page, 'First Book', LONG_NAME);
  await showCollection(page, LONG_NAME);
}

/** What the library's controls look like, and which rule of the layout
    they break: the buttons of each group under the view (a group is a
    child of the library's view, or a button that is one), grouped into
    lines by where they are, measured against the search field */
function geometry() {
  const visible = e => e.checkVisibility() && e.getClientRects().length > 0;
  const search = document.getElementById('library-search-box').getBoundingClientRect();
  const groups = [...document.getElementById('library-view').children].filter(visible).map(group => {
    const buttons = group.matches('button') ? [group] : [...group.querySelectorAll('button')].filter(visible);
    const boxes = buttons.map(b => b.getBoundingClientRect()).sort((a, b) => a.top - b.top || a.left - b.left);
    const lines = [];
    for (const box of boxes) {
      const line = lines.find(l => Math.abs(l[0].top - box.top) < 2);
      if (line) line.push(box); else lines.push([box]);
    }
    for (const line of lines) line.sort((a, b) => a.left - b.left);
    return { id: group.id, lines };
  }).filter(group => group.lines.length > 0);
  const lines = groups.flatMap(group => group.lines).sort((a, b) => a[0].top - b[0].top);
  const all = lines.flat();
  const gaps = [];
  for (const line of lines) for (let k = 1; k < line.length; k++) gaps.push(line[k].left - line[k - 1].right);
  for (let k = 1; k < lines.length; k++) gaps.push(lines[k][0].top - Math.max(...lines[k - 1].map(b => b.bottom)));
  const heights = all.map(b => b.height);
  const lefts = lines.map(line => line[0].left);
  const spread = list => (list.length ? Math.max(...list) - Math.min(...list) : 0);
  const broken = [];
  if (spread(heights) > 1) broken.push('height');
  if (spread(gaps) > 1) broken.push('gap');
  if (lefts.some(left => Math.abs(left - search.left) > 1)) broken.push('left-edge');
  if (groups.some(group => group.lines.length > 1 && group.lines.some(line => line.length < 2))) broken.push('lone-button');
  const round = list => list.map(n => Math.round(n * 10) / 10);
  return {
    broken, search: Math.round(search.left * 10) / 10, heights: round([...new Set(round(heights))]), gaps: round([...new Set(round(gaps))]),
    lefts: round([...new Set(round(lefts))]),
    groups: groups.map(group => ({ id: group.id, lines: group.lines.map(line => line.map(b => Math.round(b.width))) })),
  };
}

/** Turns the window to portrait or landscape: the viewport's sides swapped */
async function windowed(page, landscape) {
  const { width, height } = page.viewportSize();
  const long = Math.max(width, height);
  const short = Math.min(width, height);
  await page.setViewportSize(landscape ? { width: long, height: short } : { width: short, height: long });
}

for (const percent of [100, 200]) {
  test.describe(`at ${percent}%`, () => {
    if (percent > 100) test.use({ isMobile: true });
    for (const landscape of [false, true]) {
      test(`the library's controls are aligned with a collection shown, in ${landscape ? 'landscape' : 'portrait'}`, async ({ page }, testInfo) => {
        if (percent > 100) await page.addInitScript(scaledBy(percent));
        await windowed(page, landscape);
        const errors = await start(page);
        await importFiles(page, [
          epubFile({ title: 'First Book', author: 'A' }),
          epubFile({ title: 'Second Book', author: 'B' }),
        ], 2);
        await makeCollection(page, 'First Book', 'Amber');
        await makeCollection(page, 'Second Book', 'To read');
        await makeCollection(page, 'First Book', LONG_NAME);
        await showCollection(page, LONG_NAME);
        if (percent > 100) {
          expect(await page.evaluate(() => parseFloat(getComputedStyle(document.body).fontSize)), 'the scale reached the app').toBeGreaterThan(16 * percent / 100 - 1);
        }
        const seen = await page.evaluate(geometry);
        await testInfo.attach('geometry', { body: JSON.stringify(seen, null, 1), contentType: 'application/json' });
        expect(seen.broken, JSON.stringify(seen)).toEqual([]);
        // the filters and the collection are the only buttons under the search: no Rename or Delete beside them
        await expect(page.locator('#library-view').getByRole('button', { name: /^(Rename|Delete collection)/ })).toHaveCount(0);
        expect(errors).toEqual([]);
      });
    }
  });
}

// The checks above fail when a rule of the layout is broken: each class
// is injected here, by a style sheet the page adopts, and named
const injections = {
  'height': '#filter-unread { height: 90px; }',
  'gap': '#filter-books-first { gap: 30px; }',
  'left-edge': '#collection-button { margin-left: 12px; }',
  'lone-button': '.segpair { display: contents; } #filter-finished { flex: 1 0 100%; }',
};

for (const [broken, style] of Object.entries(injections)) {
  test(`the geometry check names a broken ${broken}`, async ({ page }) => {
    await libraryWithCollections(page);
    expect((await page.evaluate(geometry)).broken, 'before the injection').toEqual([]);
    await page.evaluate(css => {
      const sheet = new CSSStyleSheet();
      sheet.replaceSync(css);
      document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
    }, style);
    expect((await page.evaluate(geometry)).broken).toContain(broken);
  });
}

// The collection is one button that names the collection shown and opens
// a menu: its choices (All books and each collection, the shown one
// checked) and, for the shown one, Rename and Delete
test('the collection button names the collection shown and its menu holds the choices, Rename and Delete', async ({ page }) => {
  const errors = await start(page);
  await importFiles(page, [
    epubFile({ title: 'First Book', author: 'A' }),
    epubFile({ title: 'Second Book', author: 'B' }),
  ], 2);
  await expect(collectionButton(page)).toBeHidden();
  await makeCollection(page, 'First Book', 'Amber');
  await expect(collectionButton(page)).toHaveText(/Collection:\s*All books/);
  // the menu: every book's choice checked, no action while none is shown
  await collectionButton(page).click();
  await expect(collectionMenu(page)).toBeVisible();
  await expect(collectionMenu(page).getByRole('menuitemradio', { checked: true })).toHaveText(['All books']);
  await expect(collectionMenu(page).getByRole('menuitem', { name: 'Rename collection' })).toBeHidden();
  await expect(collectionMenu(page).getByRole('menuitem', { name: 'Delete collection' })).toBeHidden();
  // Escape closes it, the focus back on its button
  await page.keyboard.press('Escape');
  await expect(collectionMenu(page)).toBeHidden();
  await expect(collectionButton(page)).toBeFocused();
  // one chosen: the button names it, the books are its books
  await showCollection(page, 'Amber');
  await expect(collectionButton(page)).toHaveText(/Collection:\s*Amber/);
  await expect(cards(page)).toHaveCount(1);
  await collectionButton(page).click();
  await expect(collectionMenu(page).getByRole('menuitemradio', { checked: true })).toHaveText(['Amber']);
  await expect(collectionMenu(page).getByRole('menuitem', { name: 'Rename collection' })).toBeVisible();
  await expect(collectionMenu(page).getByRole('menuitem', { name: 'Delete collection' })).toBeVisible();
  // Rename closes the menu and asks for the name
  await collectionMenu(page).getByRole('menuitem', { name: 'Rename collection' }).click();
  await expect(collectionMenu(page)).toBeHidden();
  const name = dialog(page, 'Rename collection').getByRole('textbox', { name: 'Name' });
  await expect(name).toHaveValue('Amber');
  await name.fill('Gold');
  await name.press('Enter');
  await expect(collectionButton(page)).toHaveText(/Collection:\s*Gold/);
  // Delete closes the menu; the last collection gone, the button goes with it
  await collectionButton(page).click();
  await collectionMenu(page).getByRole('menuitem', { name: 'Delete collection' }).click();
  await expect(collectionMenu(page)).toBeHidden();
  await expect(collectionButton(page)).toBeHidden();
  await expect(cards(page)).toHaveCount(2);
  expect(errors).toEqual([]);
});
