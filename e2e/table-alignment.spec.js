// The alignment of table parts a book's style sheet gives (#868): the columns
// of an aligned equation and of a cases equation, and the cells of a plain
// table, are aligned as the book's sheet says, though the rest of the sheet
// stays unapplied (#411). Keyword: publisher alignment.

import { test, expect } from './fixtures.js';
import {
  start, readBook, bookPage, showChrome, control, dialog,
} from './helpers.js';
import { tableAlignmentBook } from './table-alignment-books.js';

const contents = page => dialog(page, 'Contents');

/** The chapter with the label, from the contents */
async function chapterNamed(page, label) {
  await showChrome(page);
  await control(page, 'Contents').click();
  await contents(page).getByRole('tabpanel', { name: 'Contents' }).getByRole('button', { name: label, exact: true }).click();
  await expect(contents(page)).toBeHidden();
}

/** Where the content of each cell of the rows sits, in the cell: the room left of it and right of it */
const roomsOf = (page, tableSelector, cellSelector) => bookPage(page).evaluate((doc, { tableSelector, cellSelector }) => {
  const table = doc.querySelectorAll(tableSelector)[0];
  return [...table.querySelectorAll('tr, mtr')].map(row => [...row.querySelectorAll(cellSelector)].map(cell => {
    const cellBox = cell.getBoundingClientRect();
    const range = document.createRange();
    range.selectNodeContents(cell);
    const content = range.getBoundingClientRect();
    return { left: content.left - cellBox.left, right: cellBox.right - content.right, text: cell.textContent.trim() };
  }));
}, { tableSelector, cellSelector });

const near = (a, b) => Math.abs(a - b) <= 1;

/** The column of cells k of the rows */
const column = (rows, k) => rows.map(row => row[k]);

const flushLeft = cells => cells.every(cell => near(cell.left, cells[0].left)) && cells.some(cell => cell.right > cells[0].right + 5 || cells[0].right > cell.right + 5);
const flushRight = cells => cells.every(cell => near(cell.right, cells[0].right)) && cells.some(cell => cell.left > cells[0].left + 5 || cells[0].left > cell.left + 5);
const centred = cells => cells.every(cell => near(cell.left, cell.right));

test('the columns of an aligned equation are right then left, as the book\'s sheet says', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, tableAlignmentBook.opts);
  const rows = await roomsOf(page, 'math', 'mtd');
  expect(rows.length, 'two rows').toBe(2);
  expect(flushRight(column(rows, 0)), JSON.stringify(column(rows, 0))).toBe(true);
  expect(flushLeft(column(rows, 1)), JSON.stringify(column(rows, 1))).toBe(true);
  expect(errors).toEqual([]);
});

test('the columns of a cases equation are left aligned, as the book\'s sheet says', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, tableAlignmentBook.opts);
  const rows = await bookPage(page).evaluate(doc => {
    const table = doc.querySelectorAll('math')[1];
    return [...table.querySelectorAll('mtr')].map(row => [...row.querySelectorAll('mtd')].map(cell => {
      const cellBox = cell.getBoundingClientRect();
      const range = document.createRange();
      range.selectNodeContents(cell);
      const content = range.getBoundingClientRect();
      return { left: content.left - cellBox.left, right: cellBox.right - content.right, text: cell.textContent.trim() };
    }));
  });
  expect(rows.length, 'two rows').toBe(2);
  expect(flushLeft(column(rows, 0)), JSON.stringify(column(rows, 0))).toBe(true);
  expect(flushLeft(column(rows, 1)), JSON.stringify(column(rows, 1))).toBe(true);
  expect(errors).toEqual([]);
});

test('the cells of a plain table are aligned by the book\'s sheet and by a style attribute, and a paragraph\'s rule is not applied', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, tableAlignmentBook.opts);
  await chapterNamed(page, 'Ledger');
  const rows = await roomsOf(page, 'table', 'td');
  expect(rows.length, 'two rows').toBe(2);
  expect(flushRight(column(rows, 0)), `the sheet's right: ${JSON.stringify(column(rows, 0))}`).toBe(true);
  expect(centred(column(rows, 1)), `the sheet's centre: ${JSON.stringify(column(rows, 1))}`).toBe(true);
  expect(flushRight(column(rows, 2)), `the style attribute's right: ${JSON.stringify(column(rows, 2))}`).toBe(true);
  // the rest of the sheet is not applied: a paragraph is aligned by the reader's settings (#411)
  const paragraph = await bookPage(page).evaluate(doc => getComputedStyle([...doc.querySelectorAll('p')].find(p => p.textContent.startsWith('sheet-paragraph'))).textAlign);
  expect(paragraph).not.toBe('right');
  expect(errors).toEqual([]);
});
