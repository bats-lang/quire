// Fallbacks of math (#408): when MathML is drawn, its alternative text and
// its fallback picture are not shown beside it, and MathML the browser or
// the reader leaves out, or that is broken, degrades where it stands: the
// words around it are still there.
//
// By research (quire#408's comment): EPUB 3.3 and the MathML specification
// make altimg and alttext the fallback for a system that cannot draw the
// math (the DAISY knowledge base: "fallback images via the altimg
// attribute" for readers that cannot render MathML). Quire's pages are
// drawn by a browser engine that draws MathML Core, so the fallback is not
// needed, and showing it would show every equation twice; the equation is
// the content, the picture and the text only stand in for it.

import { test, expect } from './fixtures.js';
import { start, bookPage, importFiles, openBook, rawFile, cards } from './helpers.js';
import { block, readMathBook, MATHML_NAMESPACE } from './math-helpers.js';

/** The text the reader sees in the page: the text of its blocks, with the words of no attribute */
const shownText = page => bookPage(page).evaluate(doc => doc.innerText);

test('alttext is not shown when the MathML is drawn', async ({ page }) => {
  const errors = await start(page);
  await readMathBook(page, 'alttext');
  const shown = await shownText(page);
  expect(shown).not.toContain('unseen words');
  const found = await bookPage(page).evaluate((doc, namespace) => {
    const maths = [...doc.querySelectorAll('math')];
    return {
      count: maths.length,
      drawn: maths.map(m => m.namespaceURI === namespace && m.getBoundingClientRect().width > 0 && !!m.querySelector('mfrac, msqrt')),
      // no element carries the words as text or as a tooltip
      anywhere: [...doc.querySelectorAll('*')].some(e => e.textContent.includes('unseen words') || (e.getAttribute('title') || '').includes('unseen words')),
      text: maths.map(m => m.textContent.replace(/\s+/g, '')),
    };
  }, MATHML_NAMESPACE);
  expect(found.count).toBe(2);
  expect(found.drawn).toEqual([true, true]);
  expect(found.anywhere).toBe(false);
  expect(found.text).toEqual(['x=12', 'y=2']);
  expect(shown).toContain('The paragraph after.');
  expect(errors).toEqual([]);
});

test('altimg is not shown beside the MathML: the equation is there once', async ({ page }) => {
  const errors = await start(page);
  await readMathBook(page, 'altimg');
  await expect(block(page, 'altimg-after')).toBeVisible();
  const found = await bookPage(page).evaluate(doc => ({
    pictures: doc.querySelectorAll('img').length,
    inMath: doc.querySelectorAll('math img, math image').length,
    fractions: doc.querySelectorAll('math mfrac').length,
    mathWidth: doc.querySelector('math').getBoundingClientRect().width,
    text: window.found(doc, 'altimg-inline').innerText.replace(/\s+/g, ' ').trim(),
  }));
  expect(found.fractions).toBe(1);
  expect(found.mathWidth).toBeGreaterThan(0);
  expect(found.pictures, 'no picture beside the equation').toBe(0);
  expect(found.inMath).toBe(0);
  expect(found.text).not.toContain('equals');
  expect(errors).toEqual([]);
});

/** The paragraph ids of a chapter that must all be there, in order, each below the one before it,
    and the words that end each: the chapter beyond the odd equation is rendered */
async function expectChapterRenders(page, ids, ending = 'ends here.') {
  const found = await bookPage(page).evaluate((doc, ids) => ids.map(id => {
    const e = window.found(doc, id);
    const r = e ? e.getBoundingClientRect() : null;
    return { id, there: !!e, top: r ? r.top : -1, height: r ? r.height : 0, text: e ? e.innerText.replace(/\s+/g, ' ').trim() : '' };
  }), ids);
  let last = -Infinity;
  for (const row of found) {
    expect(row.there, `${row.id} is in the page`).toBe(true);
    expect(row.height, `${row.id} has a height`).toBeGreaterThan(0);
    expect(row.top, `${row.id} is below the paragraph before`).toBeGreaterThan(last);
    last = row.top;
    if (row.id.includes('-before') || row.id.includes('-after')) continue;
    expect(row.text.endsWith(ending), `${row.id} still ends with its own words: ${row.text}`).toBe(true);
  }
  return found;
}

for (const [name, ids, shows] of [
  ['degraded', ['degraded-before', 'degraded-enclose', 'degraded-fenced', 'degraded-stack', 'degraded-glyph', 'degraded-good', 'degraded-after'], { 'degraded-enclose': 'x+1', 'degraded-fenced': 'ab', 'degraded-stack': '12+34', 'degraded-good': '7+8' }],
  ['degenerate', ['degenerate-before', 'degenerate-empty', 'degenerate-table', 'degenerate-size', 'degenerate-good', 'degenerate-after'], { 'degenerate-size': 'q', 'degenerate-good': '7+8' }],
  ['malformed', ['malformed-before', 'malformed-fraction', 'malformed-root', 'malformed-unknown', 'malformed-good', 'malformed-after'], { 'malformed-good': '7+8' }],
]) {
  test(`${name} MathML degrades where it stands: the rest of the chapter is drawn`, async ({ page }) => {
    const errors = await start(page);
    await readMathBook(page, name);
    await expect(block(page, ids[ids.length - 1])).toBeVisible();
    await expectChapterRenders(page, ids);
    // what is left of an equation is its content, in its place, and a good one beside is drawn as ever
    const text = await bookPage(page).evaluate((doc, ids) => Object.fromEntries(ids.map(id => [id, window.found(doc, id).textContent.replace(/\s+/g, '')])), ids);
    for (const [id, part] of Object.entries(shows)) expect(text[id], id).toContain(part);
    // an equation does not spill out of its paragraph
    const spill = await bookPage(page).evaluate((doc, ids) => ids.filter(id => {
      const p = window.found(doc, id).getBoundingClientRect();
      return [...window.found(doc, id).querySelectorAll('math, math *')].some(e => {
        const r = e.getBoundingClientRect();
        return r.width > 0 && (r.top < p.top - 2 || r.bottom > p.bottom + 2);
      });
    }), ids);
    expect(spill).toEqual([]);
    const good = block(page, ids[ids.length - 2]).locator('math');
    await expect(good).toHaveCount(1);
    expect(await good.evaluate(e => e.namespaceURI)).toBe(MATHML_NAMESPACE);
    expect((await good.boundingBox()).width).toBeGreaterThan(10);
    expect(errors).toEqual([]);
  });
}
