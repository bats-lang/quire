// The Contents' levels are in the accessibility tree (#690, epubtest.org
// nav-005): a nested entry is an item of a list in the item of its parent,
// so a screen reader announces the nesting and the level (the native
// element; no tree role, which would ask for arrow keys the rows do not
// have, and no aria-level, which the nesting already says). Each row stays
// one button named by its words.

import { test, expect } from './fixtures.js';
import { start, readBook, showChrome, control, dialog, indicator } from './helpers.js';
import { fits } from './fits.js';
import { tocLevelBooks } from './toc-levels-books.js';

const panel = page => dialog(page, 'Contents').getByRole('tabpanel', { name: 'Contents' });

test('the Contents levels are lists in lists, in the accessibility tree', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, tocLevelBooks.fourLevels.opts);
  await showChrome(page);
  await control(page, 'Contents').click();
  await expect(panel(page).getByRole('button')).toHaveCount(7);
  // one list for the top, one for each entry that has entries under it
  await expect(panel(page).getByRole('list')).toHaveCount(5);
  await expect(panel(page).getByRole('listitem')).toHaveCount(7);
  await expect(panel(page)).toMatchAriaSnapshot(`
    - list:
      - listitem:
        - button "Part One"
        - list:
          - listitem:
            - button "Section A"
            - list:
              - listitem:
                - button "Subsection A1"
                - list:
                  - listitem:
                    - button "Detail A1a"
          - listitem:
            - button "Section B"
      - listitem:
        - button "Part Two"
        - list:
          - listitem:
            - button "Section C"
  `);
  // the whole row is still the button, 48 px tall at least, and it still goes there
  for (const row of await panel(page).getByRole('button').all()) {
    expect((await row.boundingBox()).height).toBeGreaterThanOrEqual(48);
  }
  await fits(page, 'Contents, four levels deep');
  await panel(page).getByRole('button', { name: 'Subsection A1', exact: true }).click();
  await expect(dialog(page, 'Contents')).toBeHidden();
  await expect(indicator(page)).toContainText('Subsection A1');
  expect(errors).toEqual([]);
});

test('the levels indent the rows, deeper is further right', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, tocLevelBooks.fourLevels.opts);
  await showChrome(page);
  await control(page, 'Contents').click();
  const lefts = [];
  for (const name of ['Part One', 'Section A', 'Subsection A1', 'Detail A1a']) {
    const text = panel(page).getByRole('button', { name, exact: true }).locator('xpath=.');
    lefts.push(await text.evaluate(el => parseFloat(getComputedStyle(el).paddingLeft)));
  }
  for (let k = 1; k < lefts.length; k++) expect(lefts[k]).toBeGreaterThan(lefts[k - 1]);
  expect(errors).toEqual([]);
});
