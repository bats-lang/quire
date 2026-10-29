// Native MathML (#408): an equation of a chapter is drawn by the browser
// (#514), and sits in the page as text does. The fixtures are in
// math-books.js, one concern each.
//
// Inline math stands on the text's baseline and, when tall, does not run
// into the lines beside it; a display equation is a block of its own; one
// wider than the column scrolls inside itself and changes neither the page
// nor the number of pages; it scales with the reading size; and it takes
// the theme's text colour in every theme.

import { test, expect } from './fixtures.js';
import { start, bookPage, place, toLibrary, colours, rawMouse, framesPassed } from './helpers.js';
import { readMathBook, setSize, sizeRange, chooseTheme, inkIn, turnTo, MATHML_NAMESPACE } from './math-helpers.js';

// the page's fake clock is installed before each test's page opens, so the
// bars' and the hint's timers are run on it by inkIn and not waited for (#657)
test.beforeEach(async ({ page }) => {
  await page.clock.install();
});

const THEMES = ['Light', 'Dark', 'Sepia', 'Grey', 'Night'];

test('inline math is drawn as math and stands on the text baseline', async ({ page }) => {
  const errors = await start(page);
  await readMathBook(page, 'inline-baseline');
  await turnTo(page, 'baseline-row');
  const row = await bookPage(page).evaluate((doc, namespace) => {
    const paragraph = window.found(doc, 'baseline-row');
    const math = paragraph.querySelector('math');
    const texts = [];
    const walker = document.createTreeWalker(paragraph, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) if (!math.contains(node)) texts.push(node);
    const box = (node, from, to) => {
      const range = document.createRange();
      range.setStart(node, from);
      range.setEnd(node, to);
      const r = range.getBoundingClientRect();
      return { x: r.left, y: r.top, width: r.width, height: r.height };
    };
    const first = texts[0];
    const last = texts[texts.length - 1];
    const letter = math.querySelector('mi').getBoundingClientRect();
    const own = getComputedStyle(math);
    return {
      namespace: math.namespaceURI,
      display: own.display,
      before: box(first, first.data.indexOf('H'), first.data.indexOf('H') + 1),
      math: { x: letter.left, y: letter.top, width: letter.width, height: letter.height },
      after: box(last, last.data.indexOf('H'), last.data.indexOf('H') + 1),
      text: paragraph.textContent.replace(/\s+/g, ' '),
    };
  }, MATHML_NAMESPACE);
  expect(row.namespace).toBe(MATHML_NAMESPACE);
  // an inline equation, not a block: it shares the line with the words
  expect(row.display).toBe('math');
  expect(row.text).toMatch(/^baseline-row H H H and the rest/);
  // the equation's letter and the words' letters before and after it stand on one baseline: the
  // lowest ink of the flat-footed H is the same row of pixels in all three
  const before = await inkIn(page, row.before);
  const math = await inkIn(page, row.math);
  const after = await inkIn(page, row.after);
  expect(before, 'the H before the equation is drawn').not.toBeNull();
  expect(math, 'the equation is drawn').not.toBeNull();
  expect(after, 'the H after the equation is drawn').not.toBeNull();
  expect(Math.abs(math.bottom - before.bottom), `equation ${math.bottom}, text before ${before.bottom}`).toBeLessThanOrEqual(1.5);
  expect(Math.abs(math.bottom - after.bottom), `equation ${math.bottom}, text after ${after.bottom}`).toBeLessThanOrEqual(1.5);
  // and on the same line: the three are side by side
  expect(math.left).toBeGreaterThan(before.right);
  expect(after.left).toBeGreaterThan(math.right);
  expect(errors).toEqual([]);
});

test('inline math in a sentence is a real equation: its parts are MathML elements and its text reads as a sentence', async ({ page }) => {
  await start(page);
  await readMathBook(page, 'inline-baseline');
  const sentence = await bookPage(page).evaluate((doc, namespace) => {
    const paragraph = window.found(doc, 'solution');
    const maths = [...paragraph.querySelectorAll('math')];
    return {
      count: maths.length,
      allMath: maths.every(m => [m, ...m.querySelectorAll('*')].every(e => e.namespaceURI === namespace)),
      names: [...maths[0].querySelectorAll('*')].map(e => e.localName),
      // the words do not contain the markup as text
      text: paragraph.textContent.replace(/\s+/g, ' ').trim(),
      onLine: maths.map(m => {
        const r = m.getBoundingClientRect();
        const p = paragraph.getBoundingClientRect();
        return r.top >= p.top - 1 && r.bottom <= p.bottom + 1;
      }),
    };
  }, MATHML_NAMESPACE);
  expect(sentence.count).toBe(2);
  expect(sentence.allMath).toBe(true);
  expect(sentence.names).toEqual(['mi', 'mo', 'mn', 'mo', 'mn']);
  expect(sentence.text).toBe('solution The solution of x+1=3 is two, and y is another letter.');
  expect(sentence.onLine).toEqual([true, true]);
});

test('inline fractions and sums with limits do not run into the lines beside them', async ({ page }) => {
  const errors = await start(page);
  await readMathBook(page, 'inline-tall');
  const found = await bookPage(page).evaluate(doc => {
    const lineHeight = parseFloat(getComputedStyle(doc).lineHeight);
    const paragraphs = ['tall-fraction', 'tall-sum', 'tall-run'].map(id => window.found(doc, id));
    const report = [];
    for (const paragraph of paragraphs) {
      const maths = [...paragraph.querySelectorAll('math')];
      // the boxes of the words (not the equations' own text), line by line
      const words = [];
      const walker = document.createTreeWalker(paragraph, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (maths.some(m => m.contains(node))) continue;
        const range = document.createRange();
        range.selectNodeContents(node);
        for (const r of range.getClientRects()) if (r.width > 0 && r.height > 0) words.push(r);
      }
      const overlaps = [];
      maths.forEach((math, k) => {
        const box = math.getBoundingClientRect();
        for (const word of words) {
          const across = Math.min(box.right, word.right) - Math.max(box.left, word.left);
          const down = Math.min(box.bottom, word.bottom) - Math.max(box.top, word.top);
          if (across > 1 && down > 1) overlaps.push(`math ${k} over words at ${word.left.toFixed(0)},${word.top.toFixed(0)}`);
        }
        maths.slice(k + 1).forEach((other, j) => {
          const o = other.getBoundingClientRect();
          const across = Math.min(box.right, o.right) - Math.max(box.left, o.left);
          const down = Math.min(box.bottom, o.bottom) - Math.max(box.top, o.top);
          if (across > 1 && down > 1) overlaps.push(`math ${k} over math ${k + 1 + j}`);
        });
      });
      const tallest = Math.max(...maths.map(m => m.getBoundingClientRect().height));
      // the lines of the paragraph: the rows its words and equations are on
      const lines = new Set([...words].map(w => Math.round(w.top / 4)));
      report.push({ id: paragraph.id, overlaps, tallest, count: maths.length, lines: lines.size, height: paragraph.getBoundingClientRect().height });
    }
    return { lineHeight, report };
  });
  for (const row of found.report) {
    expect(row.overlaps, `${row.id}: equations over words`).toEqual([]);
    // the equations are taller than a line of the words: the test is of something that could overlap
    expect(row.tallest, `${row.id}: the tallest equation against a line`).toBeGreaterThan(found.lineHeight * 0.9);
    // the paragraph is as tall as its lines and the tall equations: it has grown, not been overrun
    expect(row.height, `${row.id}: the paragraph's height`).toBeGreaterThan(found.lineHeight * (row.lines - 0.5));
  }
  // a fraction and a sum with limits are taller than the words' line
  expect(Math.max(...found.report.map(r => r.tallest))).toBeGreaterThan(found.lineHeight * 1.1);
  expect(errors).toEqual([]);
});

test('a display equation is a block of its own, between the paragraphs before and after it', async ({ page }) => {
  const errors = await start(page);
  await readMathBook(page, 'display');
  await turnTo(page, 'display-quadratic');
  const geometry = await bookPage(page).evaluate(doc => {
    const box = e => { const r = e.getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width, height: r.height }; };
    const math = window.found(doc, 'display-quadratic');
    const inline = window.found(doc, 'display-explicit-inline');
    return {
      display: getComputedStyle(math).display,
      inlineDisplay: getComputedStyle(inline).display,
      math: box(math),
      before: box(window.found(doc, 'display-before')),
      after: box(window.found(doc, 'display-after')),
      page: box(window.found(doc, 'display-before').parentElement),
      fraction: box(math.querySelector('mfrac')),
      inlineParagraph: box(window.found(doc, 'display-inline')),
      inlineMath: box(inline),
      lineHeight: parseFloat(getComputedStyle(doc).lineHeight),
    };
  });
  expect(geometry.display).toBe('block math');
  // below the paragraph before, above the paragraph after, on lines of its own
  expect(geometry.math.top).toBeGreaterThanOrEqual(geometry.before.bottom - 1);
  expect(geometry.after.top).toBeGreaterThanOrEqual(geometry.math.bottom - 1);
  // tall: a fraction with a root is more than one line of words
  expect(geometry.math.height).toBeGreaterThan(geometry.lineHeight * 1.4);
  // as wide as the column the paragraphs are in
  expect(geometry.math.left).toBeGreaterThanOrEqual(geometry.before.left - 1);
  expect(geometry.math.right).toBeLessThanOrEqual(geometry.before.right + 1);
  // the equation is centred in its block, as a display equation is
  const middle = (geometry.fraction.left + geometry.fraction.right) / 2;
  expect(Math.abs(middle - (geometry.math.left + geometry.math.right) / 2)).toBeLessThan(geometry.math.width * 0.2);
  // display="inline" stays in its line
  expect(geometry.inlineDisplay).toBe('math');
  expect(geometry.inlineMath.top).toBeGreaterThanOrEqual(geometry.inlineParagraph.top - 1);
  expect(geometry.inlineMath.bottom).toBeLessThanOrEqual(geometry.inlineParagraph.bottom + 1);
  expect(errors).toEqual([]);
});

test('a display equation wider than the column scrolls inside itself: the page has no horizontal overflow and its pages are as many as without it', async ({ page }, testInfo) => {
  const errors = await start(page);
  // the same paragraphs with a short equation where the wide one is: the pages it has
  await readMathBook(page, 'display-wide-control');
  const control = await place(page);
  expect(control.t, 'the control chapter has pages to turn').toBeGreaterThan(1);
  await toLibrary(page);
  await readMathBook(page, 'display-wide');
  await expect.poll(async () => (await place(page)).t).toBe(control.t);
  await turnTo(page, 'wide-equation');
  const wide = await bookPage(page).evaluate(doc => {
    const math = window.found(doc, 'wide-equation');
    const box = math.getBoundingClientRect();
    const view = doc.getBoundingClientRect();
    const last = [...math.querySelectorAll('mi')].pop();
    return {
      display: getComputedStyle(math).display,
      overflowX: getComputedStyle(math).overflowX,
      clientWidth: math.clientWidth,
      scrollWidth: math.scrollWidth,
      inside: box.left >= view.left - 1 && box.right <= view.right + 1,
      documentOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
      bodyOverflow: document.body.scrollWidth - document.body.clientWidth,
      lastSymbol: last.textContent,
      pageScroll: doc.scrollLeft,
    };
  });
  expect(wide.display).toBe('block math');
  // far wider than its box, and it scrolls along its width
  expect(wide.scrollWidth).toBeGreaterThan(wide.clientWidth * 1.5);
  expect(wide.overflowX).toBe('auto');
  // its box is in the column and the document has nothing past the window
  expect(wide.inside, 'the equation lies inside the page').toBe(true);
  expect(wide.documentOverflow).toBeLessThanOrEqual(0);
  expect(wide.bodyOverflow).toBeLessThanOrEqual(0);
  const before = await place(page);
  // the wheel over the equation scrolls it
  const at = await bookPage(page).evaluate(doc => {
    const r = window.found(doc, 'wide-equation').getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  });
  await rawMouse(page, 'move', at.x, at.y);
  await rawMouse(page, 'wheel', 300, 0);
  await expect.poll(() => bookPage(page).evaluate(doc => window.found(doc, 'wide-equation').scrollLeft)).toBeGreaterThan(50);
  // a finger drag along it scrolls it too, as the browser's own gesture: a touch screen's
  if (testInfo.project.use.hasTouch) {
    const scrolled = await bookPage(page).evaluate(doc => window.found(doc, 'wide-equation').scrollLeft);
    const devtools = await page.context().newCDPSession(page);
    await devtools.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: at.x + 100, y: at.y }] });
    for (let step = 1; step <= 12; step++) {
      await devtools.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: at.x + 100 - step * 17, y: at.y }] });
      await framesPassed(page, 1);
    }
    await devtools.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await devtools.detach();
    await expect.poll(() => bookPage(page).evaluate(doc => window.found(doc, 'wide-equation').scrollLeft)).toBeGreaterThan(scrolled + 50);
  }
  // to its end, where the last symbol is in its box, and the page has not moved
  const end = await bookPage(page).evaluate(doc => {
    const math = window.found(doc, 'wide-equation');
    math.scrollLeft = math.scrollWidth;
    const box = math.getBoundingClientRect();
    const last = [...math.querySelectorAll('mi')].pop().getBoundingClientRect();
    return { shown: last.left >= box.left - 1 && last.right <= box.right + 1, pageScroll: doc.scrollLeft };
  });
  expect(end.shown, 'the last symbol is in view at the end of the equation').toBe(true);
  expect(end.pageScroll).toBe(wide.pageScroll);
  expect(await place(page)).toEqual(before);
  expect(errors).toEqual([]);
});

test('math scales with the reading size and is the same size again when the size comes back', async ({ page }) => {
  const errors = await start(page);
  await readMathBook(page, 'inline-tall');
  const heights = () => bookPage(page).evaluate(doc => ['tall-fraction', 'tall-sum'].map(id => window.found(doc, id).querySelector('math').getBoundingClientRect().height));
  const range = await sizeRange(page);
  const bigger = Math.min(range.max, Math.round(range.value * 1.5));
  const smaller = Math.max(range.min, Math.round(range.value * 0.8));
  expect(bigger).toBeGreaterThan(range.value);
  expect(smaller).toBeLessThan(range.value);
  const first = await heights();
  await setSize(page, bigger);
  await expect.poll(async () => (await heights())[0]).toBeGreaterThan(first[0] * 1.2);
  const large = await heights();
  await setSize(page, smaller);
  await expect.poll(async () => (await heights())[0]).toBeLessThan(first[0]);
  const small = await heights();
  for (const k of [0, 1]) {
    // proportional to the size, within the rounding of a font's metrics: a font's ascent, descent and a
    // fraction's bar are whole pixels, so a machine whose math font differs (CI's, 1.44 for 1.5) is off
    // by a few pixels at 18px; unscaled math (1.0) or half-scaled math is far beyond 8%
    const near = (got, want, name) => expect(Math.abs(got / want - 1), `equation ${k} ${name}: ${got}px against ${want}px`).toBeLessThan(0.08);
    near(large[k], first[k] * bigger / range.value, `at ${bigger}px against ${range.value}px`);
    near(small[k], first[k] * smaller / range.value, `at ${smaller}px against ${range.value}px`);
  }
  // and the size again is the size it was
  await setSize(page, range.value);
  await expect.poll(async () => (await heights())[0]).toBeCloseTo(first[0], 0);
  const again = await heights();
  expect(Math.abs(again[0] - first[0])).toBeLessThan(0.75);
  expect(Math.abs(again[1] - first[1])).toBeLessThan(0.75);
  expect(errors).toEqual([]);
});

for (const theme of THEMES) {
  test(`math takes the ${theme} theme's text colour`, async ({ page }) => {
    const errors = await start(page);
    await readMathBook(page, 'display');
    await chooseTheme(page, theme);
    await turnTo(page, 'display-quadratic');
    const { fg, bg } = await colours(page);
    const colour = await bookPage(page).evaluate(doc => {
      const math = window.found(doc, 'display-quadratic');
      const own = e => getComputedStyle(e).color;
      // the part of the fraction that is in the equation's box and in the window
      const whole = math.querySelector('mfrac').getBoundingClientRect();
      const box = math.getBoundingClientRect();
      const view = doc.getBoundingClientRect();
      const left = Math.max(whole.left, box.left, view.left);
      const right = Math.min(whole.right, box.right, view.right);
      const fraction = { left, top: whole.top, width: right - left, height: whole.height };
      return {
        page: own(doc),
        math: own(math),
        parts: [...math.querySelectorAll('*')].map(own),
        fraction: { x: fraction.left, y: fraction.top, width: fraction.width, height: fraction.height },
      };
    });
    // every element of the equation has the text's colour, which is the theme's
    expect(colour.math).toBe(colour.page);
    expect(new Set(colour.parts)).toEqual(new Set([colour.page]));
    expect(colour.page).toBe(`rgb(${fg.join(', ')})`);
    // and the equation is drawn in it: its most extreme pixel is the text's colour, not the ground's
    const ink = await inkIn(page, colour.fraction);
    expect(ink, 'the fraction is drawn').not.toBeNull();
    const away = (a, b) => Math.max(...a.map((v, k) => Math.abs(v - b[k])));
    expect(away(ink.strongest, fg), `strongest pixel ${ink.strongest} against the text ${fg}`).toBeLessThan(away(fg, bg) * 0.25);
    expect(errors).toEqual([]);
  });
}
