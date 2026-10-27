// The alignment of table elements a book's style sheet gives (#868): the columns
// of the aligned and cases equations of the real book
// e2e/calculus101-mathml-test.epub (made by Typst's exporter and Sphinx) are
// aligned as its _static/sphinx-typst-math.css says, and the cells of a plain
// table as its sheet and a style attribute say, though the rest of the sheets
// stays unapplied (#411). Keyword: publisher alignment.

import { fileURLToPath } from 'node:url';
import { test, expect } from './fixtures.js';
import { start, readBook, importFiles, openBook, cards, bookPage } from './helpers.js';
import { tableAlignmentBook } from './table-alignment-books.js';

const calculus = fileURLToPath(new URL('./calculus101-mathml-test.epub', import.meta.url));

/** Imports the real book and opens it */
async function readCalculus(page) {
  const before = await cards(page).count();
  await importFiles(page, [calculus], before + 1);
  await openBook(page, 'Calculus 101');
}

/** For each cell of each row of the table the content of which includes marker: the room left and right of the content in the cell, and the styles that align it */
const cellsOf = (page, marker) => bookPage(page).evaluate((doc, marker) => {
  const table = [...doc.querySelectorAll('mtable, table')].find(t => t.textContent.includes(marker));
  return [...table.querySelectorAll('mtr, tr')].map(row => [...row.children].map(cell => {
    const cellBox = cell.getBoundingClientRect();
    const range = document.createRange();
    range.selectNodeContents(cell);
    const content = range.getBoundingClientRect();
    const style = getComputedStyle(cell);
    return { left: content.left - cellBox.left, right: cellBox.right - content.right, textAlign: style.textAlign, justifyItems: style.justifyItems, text: cell.textContent.trim() };
  }));
}, marker);

const near = (a, b) => Math.abs(a - b) <= 1;
const column = (rows, k) => rows.map(row => row[k]);
const said = cells => JSON.stringify(cells);

const flushLeft = cells => cells.every(cell => near(cell.left, cells[0].left)) && cells.some(cell => cell.right > cells[0].right + 5 || cells[0].right > cell.right + 5);
const flushRight = cells => cells.every(cell => near(cell.right, cells[0].right)) && cells.some(cell => cell.left > cells[0].left + 5 || cells[0].left > cell.left + 5);
const centred = cells => cells.every(cell => near(cell.left, cell.right));

test('the columns of the aligned equation are right then left, as the book\'s sheet says', async ({ page }) => {
  const errors = await start(page);
  await readCalculus(page);
  // the equation x + t = y, y + s = z: '.typst-math mtable.aligned mtd:nth-child(odd)' is right and '(even)' left
  const rows = await cellsOf(page, '𝑡');
  expect(rows.length, 'two rows').toBe(2);
  for (const cell of column(rows, 0)) expect({ textAlign: cell.textAlign, justifyItems: cell.justifyItems }, said(column(rows, 0))).toEqual({ textAlign: 'right', justifyItems: 'end' });
  for (const cell of column(rows, 1)) expect({ textAlign: cell.textAlign, justifyItems: cell.justifyItems }, said(column(rows, 1))).toEqual({ textAlign: 'left', justifyItems: 'start' });
  expect(errors).toEqual([]);
});

test('the columns of the cases equation are left aligned, as the book\'s sheet says', async ({ page }) => {
  const errors = await start(page);
  await readCalculus(page);
  // '.typst-math mtable.cases mtd' is left: the short cell of a column sits at the start of the wide one
  const rows = await cellsOf(page, 'otherwise');
  expect(rows.length, 'two rows').toBe(2);
  expect(flushLeft(column(rows, 0)), said(column(rows, 0))).toBe(true);
  expect(flushLeft(column(rows, 1)), said(column(rows, 1))).toBe(true);
  expect(errors).toEqual([]);
});

test('the matrix, which the sheet gives no class, keeps the browser\'s alignment', async ({ page }) => {
  const errors = await start(page);
  await readCalculus(page);
  const rows = await cellsOf(page, '4');
  for (const row of rows) for (const cell of row) expect(cell.textAlign, said(rows)).toBe('-webkit-center');
  expect(errors).toEqual([]);
});

test('the cells of a plain table are aligned by the book\'s sheet and by a style attribute, and a paragraph\'s rule is not applied', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, tableAlignmentBook.opts);
  const rows = await cellsOf(page, 'Apples');
  expect(rows.length, 'two rows').toBe(2);
  expect(flushRight(column(rows, 0)), `the sheet's right: ${said(column(rows, 0))}`).toBe(true);
  expect(centred(column(rows, 1)), `the sheet's centre: ${said(column(rows, 1))}`).toBe(true);
  expect(flushRight(column(rows, 2)), `the style attribute's right: ${said(column(rows, 2))}`).toBe(true);
  // the rest of the sheet is not applied: a paragraph is aligned by the reader's settings (#411)
  const paragraph = await bookPage(page).evaluate(doc => getComputedStyle([...doc.querySelectorAll('p')].find(p => p.textContent.startsWith('sheet-paragraph'))).textAlign);
  expect(paragraph).not.toBe('right');
  expect(errors).toEqual([]);
});
