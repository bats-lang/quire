// Books whose files are in folders (#432): the IDPF samples' layout, a
// package two levels down, hrefs written as URLs (./, %20, +, non-ASCII), a
// chapter that climbs out of the container, links between chapters of
// different folders, a note in a third folder, a notes file outside the
// spine, and ids that two chapters share. The books are in folder-books.js,
// checked by epubcheck.spec.js. Every other fixture puts the package at
// OEBPS/content.opf with the chapters beside it.
//
// Decided (issue 432) from the specifications and what readers do:
// * A path-absolute href (/OEBPS/x.xhtml) is resolved from the container's
//   root (EPUB 3.3 section 4.2.4; the W3C suite's ocf-url_link-path-absolute),
//   so it is found; it is not "refused".
// * An href that climbs above the root (../../etc/passwd) is normalised as
//   the URL standard does (a ".." at the root stays at the root), and what it
//   names is looked up in the archive only: a zip has nothing outside it, and
//   epubcheck calls the href an error (RSC-026). With no such entry the
//   chapter is missing and the others work.
// * A manifest href is a URL: percent-encoding is decoded to the entry's name
//   (RFC 3986 and the URL standard; Readium's and epubcheck's resolution
//   decode it, and the archive keeps names, not URLs).

import { test, expect } from './fixtures.js';
import {
  start, readBook, place, showChrome, chapterTitle, control, dialog, jumpBack, bookPage, visibleText,
  selectText, marks, selectionButton, indicator,
} from './helpers.js';
import { folderBooks } from './folder-books.js';

const contents = page => dialog(page, 'Contents');
const rows = page => contents(page).getByRole('tabpanel', { name: 'Contents' }).getByRole('button');
const note = page => dialog(page, 'Footnote');
const link = (page, name) => bookPage(page).getByRole('link', { name, exact: true });

async function openContents(page) {
  await showChrome(page);
  await control(page, 'Contents').click();
  await expect(contents(page)).toBeVisible();
}

/** Goes to the contents entry labelled label */
async function goToEntry(page, label) {
  await openContents(page);
  await rows(page).filter({ hasText: label }).first().click();
  await expect(contents(page)).toBeHidden();
}

/** The book's pictures that were drawn, by their alternative text */
const pictures = page => bookPage(page).evaluate(doc =>
  [...doc.querySelectorAll('img')].filter(i => i.src.startsWith('blob:') && i.complete && i.naturalWidth === 1).map(i => i.alt));

for (const [name, first, second] of [['idpf', 'Alpha', 'Beta'], ['deep', 'Gamma', 'Delta']]) {
  test(`${name}: the book opens, its picture shows, and its contents and page list go to their places`, async ({ page }) => {
    const errors = await start(page);
    await readBook(page, folderBooks[name].opts);
    await expect(chapterTitle(page)).toHaveText(first);
    // ../images/a.png (../../images/a.png) from the chapter's folder
    await expect.poll(() => pictures(page)).toEqual(['picture']);
    // nav hrefs text/ch1.xhtml#x, relative to the nav document
    await goToEntry(page, `${first} x`);
    await expect.poll(() => visibleText(page)).toContain(`Target x of ${first.toLowerCase()}`);
    await goToEntry(page, `${second} y`);
    await expect(chapterTitle(page)).toHaveText(second);
    await expect.poll(() => visibleText(page)).toContain(`Target y of ${second.toLowerCase()}`);
    // the page list's hrefs are relative to the nav document too
    await openContents(page);
    await contents(page).getByRole('tab', { name: 'Pages' }).click();
    const pages = contents(page).getByRole('tabpanel', { name: 'Pages' }).getByRole('button');
    await expect(pages).toHaveText(['1', '2']);
    await pages.nth(0).click();
    await expect(contents(page)).toBeHidden();
    await expect(chapterTitle(page)).toHaveText(first);
    await openContents(page);
    await contents(page).getByRole('tab', { name: 'Pages' }).click();
    await pages.nth(1).click();
    await expect(chapterTitle(page)).toHaveText(second);
    expect(await place(page)).toMatchObject({ p: 1 });
    expect(errors).toEqual([]);
  });
}

test('chapter hrefs with ./, %20, +, and non-ASCII names are found in the archive, shown, and reached from the contents', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, folderBooks.names.opts);
  await expect(chapterTitle(page)).toHaveText('Plain');
  const chapters = [
    ['Dot', 'Dot'], ['Space', 'Space'], ['Plus', 'Plus'], ['Umlaut', 'Umlaut'], ['Raw', 'Raw'], ['Plain', 'Plain'],
  ];
  for (const [label, heading] of chapters) {
    await goToEntry(page, label);
    await expect(chapterTitle(page)).toHaveText(label);
    await expect.poll(() => visibleText(page)).toContain(heading);
  }
  // an entry with a fragment
  for (const label of ['Dot', 'Space', 'Umlaut']) {
    await goToEntry(page, `${label} t`);
    await expect.poll(() => visibleText(page)).toContain(`Target t of ${label.toLowerCase()}`);
  }
  // and reading on turns through every one of them, in the spine's order
  await goToEntry(page, 'Plain');
  const seen = [];
  for (let step = 0; step < 80 && seen.length < 6; step++) {
    // the page indicator names the chapter even while the bars are away
    const title = /^(.*?)\s·/.exec(await indicator(page).textContent())[1];
    if (seen[seen.length - 1] !== title) seen.push(title);
    await page.keyboard.press('ArrowRight');
  }
  expect(seen).toEqual(['Plain', 'Dot', 'Space', 'Plus', 'Umlaut', 'Raw']);
  expect(errors).toEqual([]);
});

test('a chapter whose href climbs out of the container is missing, a path-absolute one is the container\'s own, and the book opens', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, folderBooks.outside.opts);
  await expect(chapterTitle(page)).toHaveText('First');
  // the missing chapter leads nowhere: the panel stays and nothing is said
  await openContents(page);
  await rows(page).filter({ hasText: 'Lost' }).click();
  await expect(contents(page)).toBeVisible();
  await expect(page.getByRole('alert')).toBeHidden();
  expect(await chapterTitle(page).textContent()).toBe('First');
  // /OEBPS/three.xhtml is found from the container's root
  await rows(page).filter({ hasText: 'Third' }).click();
  await expect(contents(page)).toBeHidden();
  await expect(chapterTitle(page)).toHaveText('Third');
  await expect.poll(() => visibleText(page)).toContain('Third');
  await expect(page.getByRole('alert')).toBeHidden();
  expect(errors).toEqual([]);
});

const links = [
  ['../text/ch2.xhtml#far', 'far', 'Second', 'Far target'],
  ['ch2.xhtml with no fragment', 'to two', 'Second', 'Second 0'],
  ['#local', 'local', 'Start', 'Local target'],
  ['../text/ch1.xhtml#self (back into the same chapter)', 'self', 'Start', 'Self target'],
];
for (const [href, text, chapter, shown] of links) {
  test(`a link to ${href} goes where it names, and Back returns`, async ({ page }) => {
    const errors = await start(page);
    await readBook(page, folderBooks.links.opts);
    await expect(chapterTitle(page)).toHaveText('Start');
    await link(page, text).click();
    await expect(chapterTitle(page)).toHaveText(chapter);
    await expect.poll(() => visibleText(page)).toContain(shown);
    await expect(jumpBack(page)).toBeVisible();
    await jumpBack(page).click();
    await expect(chapterTitle(page)).toHaveText('Start');
    await expect.poll(() => visibleText(page)).toContain('Go far');
    await expect(jumpBack(page)).toBeHidden();
    expect(errors).toEqual([]);
  });
}

test('a noteref to ../notes/notes.xhtml#n1 opens the note from a chapter in another folder', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, folderBooks.links.opts);
  await link(page, '1').click();
  await expect(note(page)).toBeVisible();
  await expect(note(page)).toContainText('Note one lives in a folder of its own.');
  await note(page).getByRole('button', { name: 'Go to note' }).click();
  await expect(chapterTitle(page)).toHaveText('Notes');
  await expect(jumpBack(page)).toBeVisible();
  expect(errors).toEqual([]);
});

test('ids two chapters share: a noteref, the contents, search and highlights each stay in their own chapter', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, folderBooks.repeated.opts);
  // chapter 2's noteref opens chapter 2's note (and chapter 1's, chapter 1's)
  await link(page, '1').click();
  await expect(note(page)).toContainText('The note of chapter 1.');
  await note(page).getByRole('button', { name: 'Close' }).click();
  await goToEntry(page, 'Number 2');
  await link(page, '1').click();
  await expect(note(page)).toContainText('The note of chapter 2.');
  await note(page).getByRole('button', { name: 'Close' }).click();
  // the contents entries to ch1.xhtml#n1 and ch2.xhtml#n1 go to their own chapter
  await goToEntry(page, 'Note 1');
  await expect(chapterTitle(page)).toHaveText('Number 1');
  await expect.poll(() => visibleText(page)).toContain('The note of chapter 1.');
  await goToEntry(page, 'Note 2');
  await expect(chapterTitle(page)).toHaveText('Number 2');
  await expect.poll(() => visibleText(page)).toContain('The note of chapter 2.');
  // the page holds the chapter shown and nothing of the other
  const ids = await bookPage(page).evaluate(doc => ({
    t: doc.ownerDocument.querySelectorAll('[id="t"]').length,
    n1: doc.ownerDocument.querySelectorAll('[id="n1"]').length,
    text: doc.textContent.includes('chapter 1'),
  }));
  expect(ids.t).toBeLessThanOrEqual(1);
  expect(ids.n1).toBeLessThanOrEqual(1);
  expect(ids.text).toBe(false);
  // search finds the word in both chapters and each result goes to its own
  await page.keyboard.press('/');
  const panel = dialog(page, 'Search in book');
  await page.keyboard.type('needle');
  await expect(panel.getByRole('status')).toHaveText('2 results');
  const results = panel.getByRole('region', { name: 'Results' }).getByRole('button');
  await results.nth(1).click();
  await expect(chapterTitle(page)).toHaveText('Number 2');
  await expect.poll(() => marks(page)).toMatchObject({ size: 1, text: 'needle' });
  await page.getByRole('toolbar', { name: 'Search results' }).getByRole('button', { name: 'Close search' }).click();
  // a highlight in each chapter is its own: each chapter paints only its one
  await goToEntry(page, 'Number 1');
  await selectText(page, 0, 3);
  await selectionButton(page, 'Highlight').click();
  await expect.poll(() => marks(page)).toMatchObject({ size: 1 });
  await goToEntry(page, 'Number 2');
  await expect.poll(() => marks(page)).toMatchObject({ size: 0 });
  await selectText(page, 0, 3);
  await selectionButton(page, 'Highlight').click();
  await expect.poll(() => marks(page)).toMatchObject({ size: 1 });
  await goToEntry(page, 'Number 1');
  await expect.poll(() => marks(page)).toMatchObject({ size: 1 });
  expect(errors).toEqual([]);
});

test('a stylesheet and a style of one chapter do not size another\'s text', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, folderBooks.styles.opts);
  const sizes = async () => bookPage(page).evaluate(doc => {
    const px = e => getComputedStyle(e).fontSize;
    const all = [...doc.querySelectorAll('p')];
    const big = all.find(p => p.textContent.startsWith('Big in'));
    const plain = all.find(p => /^(One|Two) /.test(p.textContent));
    return { big: px(big), plain: px(plain), colour: getComputedStyle(big).color === getComputedStyle(plain).color };
  });
  const one = await sizes();
  await goToEntry(page, 'Styled two');
  await expect(chapterTitle(page)).toHaveText('Styled two');
  const two = await sizes();
  // the book's colours are not applied (#411), and its sizes are in proportion to the text
  // (#431): chapter 1's own 60px reaches the text as the largest size, three times the
  // reader's (the 400% rule is held), and neither it nor chapter 1's 72px reaches chapter 2,
  // whose big paragraph has no size rule and is the reader's size
  expect(parseFloat(one.big)).toBe(3 * parseFloat(one.plain));
  expect(two.big).toBe(two.plain);
  expect(two.plain).toBe(one.plain);
  expect(one.colour && two.colour).toBe(true);
  expect(errors).toEqual([]);
});

test('a link and a noteref to a notes file that the spine does not list do nothing, and say nothing', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, folderBooks.unlisted.opts);
  const before = await place(page);
  for (const name of ['the note', '1']) {
    await link(page, name).click();
    // the reader is the spine: there is no place in it for the document, so nothing opens
    await expect(note(page)).toBeHidden();
    await expect(jumpBack(page)).toBeHidden();
    await expect(page.getByRole('alert')).toBeHidden();
    expect(await place(page)).toEqual(before);
  }
  expect(errors).toEqual([]);
});

/** The content node (c<N>) of the element that holds text, in the chapter shown */
const nodeOfText = (page, text) => bookPage(page).evaluate((doc, text) => {
  const walker = doc.ownerDocument.createTreeWalker(doc, NodeFilter.SHOW_TEXT);
  for (let t = walker.nextNode(); t; t = walker.nextNode()) {
    if (!t.data.includes(text)) continue;
    for (let el = t.parentElement; el; el = el.parentElement) if (/^c\d+$/.test(el.id)) return el.id;
  }
  return null;
}, text);

/** The content node (c<N>) that the first painted range (a search hit or a highlight) starts in */
const markedNode = page => page.evaluate(() => {
  const [range] = [...CSS.highlights.values()].flatMap(h => [...h]);
  for (let el = range.startContainer.parentElement; el; el = el.parentElement) if (/^c\d+$/.test(el.id)) return el.id;
  return null;
});

test('ids two chapters share: a search hit and a highlight are at their own chapter\'s content node', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, folderBooks.repeated.opts);
  await expect(chapterTitle(page)).toHaveText('Number 1');
  const top1 = await nodeOfText(page, 'Top of 1');
  await goToEntry(page, 'Number 2');
  await expect(chapterTitle(page)).toHaveText('Number 2');
  const top2 = await nodeOfText(page, 'Top of 2');
  // the paragraph before chapter 2's heading moves the same words to other content nodes
  expect(top1).toMatch(/^c\d+$/);
  expect(top2).toMatch(/^c\d+$/);
  expect(top2).not.toBe(top1);
  // a search hit in chapter 2 is painted at chapter 2's node for its paragraph
  await page.keyboard.press('/');
  const panel = dialog(page, 'Search in book');
  await page.keyboard.type('needle');
  await expect(panel.getByRole('status')).toHaveText('2 results');
  await panel.getByRole('region', { name: 'Results' }).getByRole('button').nth(1).click();
  await expect(chapterTitle(page)).toHaveText('Number 2');
  await expect.poll(() => marks(page)).toMatchObject({ size: 1, text: 'needle' });
  expect(await markedNode(page)).toBe(await nodeOfText(page, 'Target t of chapter 2'));
  await page.getByRole('toolbar', { name: 'Search results' }).getByRole('button', { name: 'Close search' }).click();
  // a highlight in each chapter is painted at that chapter's node, and read back at it after the other chapter
  await selectText(page, 0, 3);
  await selectionButton(page, 'Highlight').click();
  await expect.poll(() => marks(page)).toMatchObject({ size: 1, text: 'Lea' });
  const lead2 = await markedNode(page);
  expect(lead2).toBe(await nodeOfText(page, 'Lead of chapter 2'));
  await goToEntry(page, 'Number 1');
  await expect.poll(() => marks(page)).toMatchObject({ size: 0 });
  await selectText(page, 0, 3);
  await selectionButton(page, 'Highlight').click();
  await expect.poll(() => marks(page)).toMatchObject({ size: 1, text: 'Top' });
  expect(await markedNode(page)).toBe(top1);
  await goToEntry(page, 'Number 2');
  await expect.poll(() => marks(page)).toMatchObject({ size: 1, text: 'Lea' });
  expect(await markedNode(page)).toBe(lead2);
  expect(errors).toEqual([]);
});

test('a stylesheet that two chapters both link sizes the text of each', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, folderBooks.shared.opts);
  const sizes = () => bookPage(page).evaluate(doc => {
    const all = [...doc.querySelectorAll('p')];
    const big = all.find(p => p.textContent.startsWith('Big in'));
    const plain = all.find(p => /^(One|Two) /.test(p.textContent));
    return { big: getComputedStyle(big).fontSize, plain: getComputedStyle(plain).fontSize };
  });
  const one = await sizes();
  await goToEntry(page, 'Shared two');
  await expect(chapterTitle(page)).toHaveText('Shared two');
  const two = await sizes();
  // the sheet's 72px rule reaches each chapter's text, held to three times the reader's size (#431)
  expect(parseFloat(one.big)).toBe(3 * parseFloat(one.plain));
  expect(two.big).toBe(one.big);
  expect(two.plain).toBe(one.plain);
  expect(errors).toEqual([]);
});
