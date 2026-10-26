// The Virtual Screen Reader (Guidepup) reads the reader's controls and the nested Contents
// inside the page (#692, #925, keyword: screen-reader). It is a simulation: its log is the
// library's rendering of the accessibility tree (names, roles, levels, states), not what NVDA
// or VoiceOver say, and it runs no live regions, so these tests catch a missing name, role,
// level or state, and the real screen readers (#926) cover the rest. Run in one project:
// the phrases are the tree's and the tree does not change with the viewport.

import { test, expect } from './fixtures.js';
import { start, readBook, showChrome, control } from './helpers.js';
import { spoken, structure } from './screen-reader.js';
import { tocLevelBooks } from './toc-levels-books.js';

test.beforeEach(({}, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'the tree is the same in every project; one reads it');
});

const topBar = '[role=navigation][aria-label="Book"]';
const bottomBar = '[role=toolbar][aria-label="Page controls"]';
const contents = '[role=dialog][aria-label="Contents"]';

async function openReader(page) {
  const errors = await start(page);
  await readBook(page, tocLevelBooks.fourLevels.opts);
  await showChrome(page);
  return errors;
}

const topBarPhrases = [
  'navigation, Book',
  'button, Back to library',
  'heading, Part One, level 1',
  'button, Bookmark this page, not pressed',
  'button, Search in book',
];

const bottomBarPhrases = [
  'toolbar, Page controls, orientated horizontally',
  'button, Previous page',
  'slider, Place in book, orientated horizontally, max value 100, min value 0, 0',
  'button, Next page',
  'button, Next chapter',
  'button, Contents',
  'button, Reading settings',
  'button, Annotations',
  'button, Read aloud, not pressed',
];

test('Virtual Screen Reader (simulation): the top bar speaks its controls by name, in order', async ({ page }) => {
  const errors = await openReader(page);
  expect(structure(await spoken(page, topBar))).toEqual(topBarPhrases);
  expect(errors).toEqual([]);
});

test('Virtual Screen Reader (simulation): the bottom bar speaks its controls by name, in order, with the page indicator first', async ({ page }) => {
  const errors = await openReader(page);
  const log = await spoken(page, bottomBar);
  expect(structure(log)).toEqual(bottomBarPhrases);
  // the page indicator is a status named Page and its words are the place
  expect(log.slice(0, 2)).toEqual(['toolbar, Page controls, orientated horizontally', 'status, Page']);
  expect(log.join(' ')).toContain('in chapter');
  expect(errors).toEqual([]);
});

test('Virtual Screen Reader (simulation): the nested Contents speaks each entry with its level', async ({ page }) => {
  const errors = await openReader(page);
  await control(page, 'Contents').click();
  const log = await spoken(page, contents);
  expect(log.slice(0, 2)).toEqual(['dialog, Contents, modal', 'dialog, Contents, modal']);
  // the tabs, then the entries: a list item of level n holds the button of its title, and the
  // levels of the four-level book are 1 to 4
  expect(structure(log)).toEqual([
    'dialog, Contents, modal',
    'dialog, Contents, modal',
    'tab, Contents, selected, 1 control, position 1, set size 2',
    'tab, Bookmarks, not selected, 1 control, position 2, set size 2',
    'button, Close',
    'listitem, level 1, position 1, set size 2',
    'button, Part One, current item',
    'listitem, level 2, position 1, set size 2',
    'button, Section A, not current item',
    'listitem, level 3, position 1, set size 1',
    'button, Subsection A1, not current item',
    'listitem, level 4, position 1, set size 1',
    'button, Detail A1a, not current item',
    'listitem, level 2, position 2, set size 2',
    'button, Section B, not current item',
    'listitem, level 1, position 2, set size 2',
    'button, Part Two, not current item',
    'listitem, level 2, position 1, set size 1',
    'button, Section C, not current item',
  ]);
  expect(errors).toEqual([]);
});

test('Virtual Screen Reader (simulation): an inaccessible control changes what is spoken, so the tests above see it', async ({ page }) => {
  const errors = await openReader(page);
  // the Contents button loses its name and the page indicator its role
  await page.evaluate(() => {
    const button = document.querySelector('[role=toolbar][aria-label="Page controls"] [aria-label="Contents"]');
    button.removeAttribute('aria-label');
    document.querySelector('[role=toolbar][aria-label="Page controls"] [role=status]').removeAttribute('role');
  });
  const log = await spoken(page, bottomBar);
  expect(structure(log)).not.toEqual(bottomBarPhrases);
  expect(log).not.toContain('button, Contents');
  expect(log).not.toContain('status, Page');
  expect(errors).toEqual([]);
});
