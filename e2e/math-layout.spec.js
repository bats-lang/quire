// Math in the page's layout and in the accessibility tree (#408): a
// display equation is never split or clipped at a page's edge, a book read
// from the right still sets an equation from the left unless the MathML
// itself says dir="rtl", and the MathML is in the accessibility tree as
// the browser puts it, with no role of Quire's.

import { test, expect } from './fixtures.js';
import { start, bookPage, place, oneColumn } from './helpers.js';
import { block, readMathBook, MATHML_NAMESPACE } from './math-helpers.js';

test('in pages, a display equation is not split or clipped at a page boundary', async ({ page }) => {
  const errors = await start(page);
  await readMathBook(page, 'page-boundary');
  await oneColumn(page);
  const { t } = await place(page);
  expect(t, 'the chapter has many pages').toBeGreaterThan(4);
  const seen = new Set();
  for (let at = 1; at <= t; at++) {
    await expect.poll(async () => (await place(page)).p).toBe(at);
    const found = await bookPage(page).evaluate(doc => {
      const view = doc.getBoundingClientRect();
      return [...doc.querySelectorAll('math[display=block]')].map(m => {
        const rects = [...m.getClientRects()];
        const r = m.getBoundingClientRect();
        const touches = r.right > view.left + 1 && r.left < view.right - 1;
        return {
          id: m.id, touches, fragments: rects.length,
          inside: r.left >= view.left - 1 && r.right <= view.right + 1 && r.top >= view.top - 1 && r.bottom <= view.bottom + 1,
          // the whole equation is drawn: its box is as tall as its content
          scrollHeight: m.scrollHeight, clientHeight: m.clientHeight,
        };
      });
    });
    for (const m of found.filter(m => m.touches)) {
      seen.add(m.id);
      expect(m.fragments, `${m.id} is one box on page ${at}`).toBe(1);
      expect(m.inside, `${m.id} lies wholly inside page ${at}`).toBe(true);
      expect(m.scrollHeight, `${m.id} is not clipped`).toBeLessThanOrEqual(m.clientHeight + 1);
    }
    if (at < t) {
      await page.keyboard.press('ArrowRight');
    }
  }
  expect(seen.size, 'every equation was seen whole on a page').toBe(24);
  expect(errors).toEqual([]);
});

test('in a Hebrew book an equation is set left to right unless its MathML says dir="rtl"', async ({ page }) => {
  const errors = await start(page);
  await readMathBook(page, 'hebrew');
  const found = await bookPage(page).evaluate(doc => {
    const order = id => {
      const math = window.found(doc, id);
      const x = [...math.querySelectorAll('mi, mo, mn')].map(e => e.getBoundingClientRect().left);
      return { direction: getComputedStyle(math).direction, increasing: x.every((v, k) => k === 0 || v > x[k - 1]), decreasing: x.every((v, k) => k === 0 || v < x[k - 1]), text: math.textContent.replace(/\s+/g, '') };
    };
    return { page: getComputedStyle(doc).direction, inline: order('hebrew-math'), display: order('hebrew-display'), rtl: order('hebrew-rtl') };
  });
  expect(found.page).toBe('rtl');
  expect(found.inline.text).toBe('x=1+2');
  expect(found.inline.increasing, 'the inline equation reads from the left').toBe(true);
  expect(found.display.increasing, 'the display equation reads from the left').toBe(true);
  expect(found.rtl.decreasing, 'dir="rtl" sets it from the right').toBe(true);
  expect(found.inline.direction).toBe('ltr');
  expect(found.display.direction).toBe('ltr');
  expect(found.rtl.direction).toBe('rtl');
  expect(errors).toEqual([]);
});

test('MathML is in the accessibility tree and Quire adds no role', async ({ page }) => {
  const errors = await start(page);
  await readMathBook(page, 'display');
  const dom = await bookPage(page).evaluate((doc, namespace) => {
    const maths = [...doc.querySelectorAll('math')];
    const parts = maths.flatMap(m => [m, ...m.querySelectorAll('*')]);
    return {
      count: maths.length,
      namespaced: parts.every(e => e.namespaceURI === namespace),
      roles: parts.filter(e => e.hasAttribute('role')).map(e => e.localName),
      anywhereMathRole: doc.ownerDocument.querySelectorAll('[role=math]').length,
      hidden: maths.filter(m => m.closest('[aria-hidden=true], [hidden], [inert]') !== null).length,
      ariaOnMath: maths.filter(m => m.hasAttribute('aria-hidden') || m.hasAttribute('aria-label')).length,
    };
  }, MATHML_NAMESPACE);
  expect(dom.count).toBe(2);
  expect(dom.namespaced).toBe(true);
  expect(dom.roles, 'Quire sets no role on MathML').toEqual([]);
  expect(dom.anywhereMathRole).toBe(0);
  expect(dom.hidden, 'no MathML is hidden from the tree').toBe(0);
  expect(dom.ariaOnMath).toBe(0);
  // the browser's own tree: a MathMLMath node (the role of ARIA math) for each equation, not ignored, holding the equation's letters
  const devtools = await page.context().newCDPSession(page);
  await devtools.send('Accessibility.enable');
  const { nodes } = await devtools.send('Accessibility.getFullAXTree');
  await devtools.detach();
  const maths = nodes.filter(n => !n.ignored && n.role && n.role.value === 'MathMLMath');
  expect(maths.length, 'a MathMLMath node (the role of ARIA math) for each equation').toBe(2);
  const byId = new Map(nodes.map(n => [n.nodeId, n]));
  const texts = id => {
    const n = byId.get(id);
    if (!n) return '';
    const own = n.role && n.role.value === 'StaticText' ? (n.name && n.name.value) || '' : '';
    return own + (n.childIds || []).map(texts).join('');
  };
  const content = maths.map(n => texts(n.nodeId).replace(/\s+/g, ''));
  expect(content.some(t => t.includes('\u00B1') && t.includes('2')), `the equation's characters are in its subtree: ${content}`).toBe(true);
  expect(errors).toEqual([]);
});
