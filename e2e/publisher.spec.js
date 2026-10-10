// Publisher styling against the reader's settings (#411): the book's own
// CSS is dropped (a `<style>`, a style attribute, `!important`, a media
// rule), and so are obsolete presentational attributes, so nothing of it
// fights the text size, the theme, the margins or the page's width. The
// books are in publisher-books.js, checked by epubcheck.spec.js.
//
// Decided (issue 411), against Readium CSS (Thorium): it keeps the
// publisher's styles unless the reader turns on "advanced" settings, and
// an `!important` in a book can beat a reader's setting. Quire applies the
// publisher's CSS never, so no setting is beaten and none is needed:
// text-align, line-height and font-family come from the settings
// (Justify, the spacings, the Font row) alone. What the CSS dropped
// hid (`display:none` by a rule or a style attribute) is shown, since
// there is no CSS to say it; the `hidden` attribute is the HTML's own
// word for it and is kept.

import { test, expect } from './fixtures.js';
import {
  start, readBook, bookPage, showChrome, control, dialog, openReadingSettings, readingSettings,
} from './helpers.js';
import { publisherBooks } from './publisher-books.js';

const contents = page => dialog(page, 'Contents');

/** The chapter with the label, from the contents */
async function chapterNamed(page, label) {
  await showChrome(page);
  await control(page, 'Contents').click();
  await contents(page).getByRole('tabpanel', { name: 'Contents' }).getByRole('button', { name: label, exact: true }).click();
  await expect(contents(page)).toBeHidden();
}

const paragraph = (page, text) => bookPage(page).locator('p', { hasText: text }).first();
const styleOf = (locator, props) => locator.evaluate((e, props) => {
  const cs = getComputedStyle(e);
  return Object.fromEntries(props.map(p => [p, cs[p]]));
}, props);

async function theme(page, name) {
  await openReadingSettings(page, 'Look');
  await readingSettings(page).getByRole('group', { name: 'Theme' }).getByRole('button', { name, exact: true }).click();
  await page.keyboard.press('Escape');
  await expect(dialog(page, 'Reading settings')).toBeHidden();
}

test('a book\'s pixel, point and !important sizes do not stop the text size setting', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, publisherBooks.styled.opts);
  const sizes = async () => {
    const base = (await styleOf(bookPage(page), ['fontSize'])).fontSize;
    const out = [base];
    for (const t of ['Pixel sized', 'Point sized', 'Important inline']) out.push((await styleOf(paragraph(page, t), ['fontSize'])).fontSize);
    return out;
  };
  const before = await sizes();
  expect(new Set(before).size).toBe(1);
  await openReadingSettings(page, 'Look');
  await readingSettings(page).getByRole('slider', { name: 'Size' }).fill('28');
  await page.keyboard.press('Escape');
  await expect.poll(sizes).toEqual(['28px', '28px', '28px', '28px']);
  // the heading's 6pt !important is not its size either: larger than the text
  const heading = await bookPage(page).locator('h1').first().evaluate(e => parseFloat(getComputedStyle(e).fontSize));
  expect(heading).toBeGreaterThan(28);
  expect(errors).toEqual([]);
});

// the page's colours, and every element's own: no element but the page
// has a ground of its own, and every text is the theme's, at 4.5:1 or more
async function colourFaults(page) {
  return bookPage(page).evaluate(root => {
    const rgba = s => { const m = s.match(/[\d.]+/g).map(Number); return { r: m[0], g: m[1], b: m[2], a: m.length > 3 ? m[3] : 1 }; };
    const lum = c => {
      const f = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
      return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    };
    const ground = (() => {
      for (let el = root; el; el = el.parentElement) {
        const c = rgba(getComputedStyle(el).backgroundColor);
        if (c.a > 0.5) return c;
      }
      return { r: 255, g: 255, b: 255, a: 1 };
    })();
    const faults = [];
    for (const e of root.querySelectorAll('*')) {
      if (!e.getClientRects().length) continue;
      const cs = getComputedStyle(e);
      const own = rgba(cs.backgroundColor);
      if (own.a > 0.05 && lum(own) !== lum(ground) && !e.closest('mark, [class*=mark]')) faults.push(`${e.tagName} has its own ground ${cs.backgroundColor}`);
      if (e.children.length === 0 && e.textContent.trim()) {
        const fg = lum(rgba(cs.color)), bg = lum(ground);
        const ratio = (Math.max(fg, bg) + 0.05) / (Math.min(fg, bg) + 0.05);
        if (ratio < 4.5) faults.push(`${e.tagName} "${e.textContent.trim().slice(0, 20)}" is ${ratio.toFixed(1)}:1`);
      }
    }
    return faults;
  });
}

for (const name of ['styled', 'legacy']) {
  test(`hardcoded black text and light grounds (${name}) are legible, with no slab, in every theme`, async ({ page }) => {
    const errors = await start(page);
    await readBook(page, publisherBooks[name].opts);
    if (name === 'styled') await chapterNamed(page, 'Colours');
    for (const t of ['Light', 'Dark', 'Sepia', 'Grey', 'Night']) {
      await theme(page, t);
      expect(await colourFaults(page), `in the ${t} theme`).toEqual([]);
    }
    expect(errors).toEqual([]);
  });
}

test('fixed margins, paddings and widths do not push text off the page or fight the margins setting', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, publisherBooks.styled.opts);
  await chapterNamed(page, 'Margins');
  const plain = await styleOf(paragraph(page, 'Padded'), ['marginLeft', 'paddingLeft', 'width']);
  const wide = await styleOf(paragraph(page, 'Fixed margin and width'), ['marginLeft', 'width']);
  expect(wide.marginLeft).toBe('0px');
  expect(wide.width).not.toBe('600px');
  expect(plain.paddingLeft).toBe('0px');
  // no horizontal overflow of the page, and the text within it
  const box = await bookPage(page).boundingBox();
  for (const t of ['Fixed margin and width', 'Padded']) {
    const b = await paragraph(page, t).boundingBox();
    expect(b.x).toBeGreaterThanOrEqual(box.x - 1);
    expect(b.x + b.width).toBeLessThanOrEqual(box.x + box.width + 1);
  }
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  // the margins setting still sets the page's own
  const first = bookPage(page).locator('p').first();
  const before = (await styleOf(first, ['paddingLeft'])).paddingLeft;
  await openReadingSettings(page, 'Page');
  await readingSettings(page).getByRole('slider', { name: 'Margins' }).fill('4');
  await expect.poll(async () => (await styleOf(first, ['paddingLeft'])).paddingLeft).not.toBe(before);
  expect(errors).toEqual([]);
});

test('a publisher\'s text-align, line-height and font-family are not applied; the settings are', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, publisherBooks.styled.opts);
  await chapterNamed(page, 'Alignment');
  const props = ['textAlign', 'lineHeight', 'fontFamily'];
  const styled = await styleOf(paragraph(page, 'Right aligned'), props);
  const page_ = await styleOf(bookPage(page), props);
  expect(styled.textAlign).not.toBe('right');
  expect(styled.fontFamily).toBe(page_.fontFamily);
  expect(styled.fontFamily).not.toMatch(/Courier/i);
  expect(styled.lineHeight).toBe(page_.lineHeight);
  // Justify is the reader's
  await openReadingSettings(page, 'Page');
  await readingSettings(page).getByRole('button', { name: 'Justify text', exact: true }).click();
  await expect.poll(async () => (await styleOf(paragraph(page, 'Right aligned'), ['textAlign'])).textAlign).toBe('justify');
  expect(errors).toEqual([]);
});

test('the hidden attribute keeps text hidden; a rule or style that hid text is not applied, nor is a media rule', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, publisherBooks.styled.opts);
  await chapterNamed(page, 'Hidden');
  // the text laid out (what is hidden is not in it), on the page's pages or not
  const text = await bookPage(page).evaluate(doc => doc.innerText);
  expect(text).toContain('Shown text.');
  expect(text).not.toContain('Hidden by attribute.');
  // what only CSS said to hide is shown: the CSS is not applied
  for (const t of ['Hidden inline.', 'Hidden by class.', 'Media rule.']) expect(text, t).toContain(t);
  expect(errors).toEqual([]);
});

test('obsolete presentational attributes (font, bgcolor, width) do not set a size, a ground or a width', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, publisherBooks.legacy.opts);
  const base = (await styleOf(bookPage(page), ['fontSize'])).fontSize;
  expect((await styleOf(paragraph(page, 'Font tag text'), ['fontSize'])).fontSize).toBe(base);
  const table = bookPage(page).locator('table').first();
  if (await table.count()) {
    // each fragment of the table within the page's width (a block over
    // several columns has a union box as wide as them all)
    const area = await bookPage(page).boundingBox();
    const widest = await table.evaluate(t => Math.max(...[...t.getClientRects()].map(r => r.width)));
    expect(widest).toBeLessThanOrEqual(area.width + 1);
  }
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  expect(errors).toEqual([]);
});
