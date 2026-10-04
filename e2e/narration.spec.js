// Narration: a book's Media Overlays (EPUB 3.3 §9) read aloud by its own
// recorded voice, the text each phrase reads marked and kept on the
// page, into the next chapter, at the speed chosen, page numbers and
// notes passed over, a table left. The narration here is silence (a WAV,
// which Playwright's Chromium plays), cut into clips of 0.6 s.

import { test, expect } from './fixtures.js';
import { silentWav } from './create-epub.js';
import {
  start, readBook, place, bookPage, chapterTitle, control, dialog, openSettings, reload, startsOnPage,
} from './helpers.js';

const CLIP = 0.6;
/** A poll every 20 ms: expect.poll's own backs off to a second, longer
    than a clip, so it can miss a phrase marked only while it is read */
const FAST = { intervals: [20] };

/** A chapter's SMIL: a seq of pars, each { id, type, seconds } or a
    nested seq { seq: type, pars }; the clips follow each other in
    audio/name, 0.6 s each unless seconds says, the last with no clipEnd
    (to the audio's end) when open */
function smil(chapter, items, { audio = 'audio/chapter1.wav', start = 0, openEnd = false } = {}) {
  let at = start;
  const total = items.reduce((n, i) => n + (i.seq ? i.pars.length : 1), 0);
  let k = 0;
  // the clock values in each of EPUB 3.3's forms
  const forms = [
    s => `0:00:${s.toFixed(3).padStart(6, '0')}`,
    s => `00:${s.toFixed(3).padStart(6, '0')}`,
    s => `${s.toFixed(1)}s`,
    s => `${Math.round(s * 1000)}ms`,
    s => `${s.toFixed(2)}`,
  ];
  const par = p => {
    const begin = forms[k % forms.length](at);
    at += p.seconds || CLIP;
    k++;
    const end = (openEnd && k === total) ? '' : ` clipEnd="${forms[(k + 2) % forms.length](at)}"`;
    return `<par id="par${k}"${p.type ? ` epub:type="${p.type}"` : ''}><text src="chapter${chapter}.xhtml#${p.id}"/>` +
      `<audio src="${audio}" clipBegin="${begin}"${end}/></par>\n`;
  };
  const body = items.map(i => i.seq
    ? `<seq epub:type="${i.seq}" epub:textref="chapter${chapter}.xhtml#${i.id}">\n${i.pars.map(par).join('')}</seq>\n`
    : par(i)).join('');
  return `<?xml version="1.0" encoding="UTF-8"?>
<smil xmlns="http://www.w3.org/ns/SMIL" xmlns:epub="http://www.idpf.org/2007/ops" version="3.0">
<body>
<seq id="body${chapter}" epub:textref="chapter${chapter}.xhtml" epub:type="bodymatter chapter">
${body}</seq>
</body>
</smil>`;
}

const filler = 'lorem ipsum dolor sit amet '.repeat(16);

/** Two narrated chapters: paragraphs one and two, then pages of text no
    clip reads, then paragraph three (on a later page); chapter 2 one
    paragraph */
function turningBook(title, store = true) {
  const unread = Array.from({ length: 14 }, (_, k) => `<p>Unread ${k} ${filler}</p>`).join('');
  return {
    title, author: 'Narration Tests',
    rawChapters: [
      {
        body: `<h1>Part 1</h1><p id="p1">Paragraph one is read first.</p><p id="p2">Paragraph two is read next.</p>${unread}<p id="p3">Paragraph three is on a later page.</p>`,
        overlay: smil(1, [{ id: 'p1' }, { id: 'p2' }, { id: 'p3' }], { openEnd: true }),
      },
      {
        body: '<h1>Part 2</h1><p id="q1">Chapter two first words.</p>',
        overlay: smil(2, [{ id: 'q1' }], { audio: 'audio/chapter2.wav' }),
      },
    ],
    extraFiles: [
      { name: 'audio/chapter1.wav', data: silentWav(3 * CLIP), mediaType: 'audio/wav', store },
      { name: 'audio/chapter2.wav', data: silentWav(CLIP), mediaType: 'audio/wav', store },
    ],
  };
}

/** Many short narrated paragraphs, several to a page */
function denseBook(title) {
  const ids = Array.from({ length: 40 }, (_, k) => `d${k + 1}`);
  return {
    title, author: 'Narration Tests',
    rawChapters: [{
      body: '<h1>Part 1</h1>' + ids.map((id, k) => `<p id="${id}">Line ${k + 1} of the many short lines here.</p>`).join(''),
      overlay: smil(1, ids.map(id => ({ id }))),
    }],
    extraFiles: [{ name: 'audio/chapter1.wav', data: silentWav(ids.length * CLIP), mediaType: 'audio/wav', store: true }],
  };
}

/** A page number between two paragraphs, and a table whose cells are
    read for 4 s each (time for its Skip table to be pressed while in
    it, whatever the machine's load) */
const CELL = 4;
function structuredBook(title) {
  return {
    title, author: 'Narration Tests',
    rawChapters: [{
      body: '<h1>Part 1</h1><p id="s1">First words.</p><div id="page2" epub:type="pagebreak" title="2">Page 2</div>' +
        '<p id="s2">Second words.</p>' +
        '<table id="tbl"><tr><td id="c1">Cell one</td></tr><tr><td id="c2">Cell two</td></tr><tr><td id="c3">Cell three</td></tr></table>' +
        '<p id="s3">After the table.</p>',
      overlay: smil(1, [
        { id: 's1' }, { id: 'page2', type: 'pagebreak' }, { id: 's2' },
        { seq: 'table', id: 'tbl', pars: [{ id: 'c1', seconds: CELL }, { id: 'c2', seconds: CELL }, { id: 'c3', seconds: CELL }] },
        { id: 's3' },
      ]),
    }],
    extraFiles: [{ name: 'audio/chapter1.wav', data: silentWav(4 * CLIP + 3 * CELL), mediaType: 'audio/wav', store: true }],
  };
}

/** The text the narration marks, its ranges joined by | */
const marked = page => page.evaluate(() => {
  const h = CSS.highlights.get('bats-mark-5');
  return h ? [...h].map(r => r.toString()).join('|') : '';
});

/** The narration's audio element's state */
const audio = page => page.evaluate(() => {
  const a = document.getElementById('narration');
  return { paused: a.paused, time: a.currentTime, rate: a.playbackRate };
});

/** Records every text the narration marks, from now on, in the page
    (every 20 ms, so a phrase of 0.6 s is never missed however slow the
    test's own steps are), and whether it was on the page shown when it
    was marked */
const watchMarks = page => page.evaluate(() => {
  window.narrationSeen = [];
  window.narrationShown = {};
  clearInterval(window.narrationWatch);
  window.narrationWatch = setInterval(() => {
    const h = CSS.highlights.get('bats-mark-5');
    const ranges = h ? [...h] : [];
    const text = ranges.map(r => r.toString()).join('|');
    if (!text || window.narrationSeen[window.narrationSeen.length - 1] === text) return;
    window.narrationSeen.push(text);
    const shown = document.querySelector('[role=document][aria-label=Page]').getBoundingClientRect();
    window.narrationShown[text] = ranges.some(r => [...r.getClientRects()].some(c => c.right > shown.left && c.left < shown.right));
  }, 20);
});
const seen = page => page.evaluate(() => window.narrationSeen);
const shownWhenMarked = (page, text) => page.evaluate(text => window.narrationShown[text], text);

/** Brings the bars up by the keyboard (a tap on the page would be a tap
    on the text the narration reads), and clicks the control name */
async function press(page, name) {
  await expect(async () => {
    if (!(await control(page, 'Previous page').isVisible())) await page.keyboard.press('t');
    await control(page, name).click({ timeout: 2000 });
  }).toPass({ timeout: 20000 });
}

const readAloud = page => control(page, 'Read aloud');

test('Read aloud plays the narration, marking each phrase as it is read', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, turningBook('Narrated'));
  await watchMarks(page);
  await press(page, 'Read aloud');
  await expect(readAloud(page)).toHaveAttribute('aria-pressed', 'true');
  await expect.poll(async () => (await audio(page)).time).toBeGreaterThan(0);
  expect((await audio(page)).paused).toBe(false);
  // a clip on a later page turns to it, as it is marked
  await expect.poll(() => seen(page)).toContain('Paragraph three is on a later page.');
  expect((await seen(page)).slice(0, 3)).toEqual(['Paragraph one is read first.', 'Paragraph two is read next.',
    'Paragraph three is on a later page.']);
  expect(await shownWhenMarked(page, 'Paragraph one is read first.')).toBe(true);
  expect(await shownWhenMarked(page, 'Paragraph three is on a later page.')).toBe(true);
  // the chapter's end goes on into the next
  await expect(chapterTitle(page)).toHaveText('Chapter 2', { timeout: 15000 });
  await expect.poll(() => seen(page)).toContain('Chapter two first words.');
  expect(await seen(page)).toEqual(['Paragraph one is read first.', 'Paragraph two is read next.',
    'Paragraph three is on a later page.', 'Chapter two first words.']);
  expect(errors).toEqual([]);
});

test('pausing stops the audio, and Read aloud goes on from the same phrase', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, denseBook('Paused'));
  await press(page, 'Read aloud');
  await expect.poll(() => marked(page), FAST).toMatch(/^Line [2-9] /);
  await press(page, 'Read aloud');
  await expect(readAloud(page)).toHaveAttribute('aria-pressed', 'false');
  const phrase = await marked(page);
  const { time, paused } = await audio(page);
  expect(paused).toBe(true);
  await page.waitForTimeout(500);
  expect((await audio(page)).time).toBe(time);
  expect(await marked(page)).toBe(phrase);
  await readAloud(page).click();
  await expect(readAloud(page)).toHaveAttribute('aria-pressed', 'true');
  expect(await marked(page)).toBe(phrase);
  await expect.poll(async () => (await audio(page)).time).toBeGreaterThan(time);
  expect(errors).toEqual([]);
});

test('a page turned by hand while the narration plays moves it to that page', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, denseBook('Turned'));
  const first = await place(page);
  expect(first.t).toBeGreaterThan(1);
  await watchMarks(page);
  await press(page, 'Read aloud');
  await expect.poll(() => marked(page), FAST).toBe('Line 1 of the many short lines here.');
  await page.keyboard.press('ArrowRight');
  await expect.poll(async () => (await place(page)).p).toBe(2);
  const opening = (await startsOnPage(page))[0];
  await expect.poll(async () => (await marked(page)).slice(0, 12), FAST).toBe(opening);
  expect((await place(page)).p).toBe(2);
  // straight there: the lines between were not read
  expect(await seen(page)).not.toContain('Line 3 of the many short lines here.');
  expect(errors).toEqual([]);
});

test('the narration speed is kept, and plays the audio at it', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, denseBook('Faster'));
  await openSettings(page);
  const sheet = dialog(page, 'Typography and theme');
  const speed = sheet.getByRole('slider', { name: 'Narration speed' });
  await expect(speed).toHaveValue('4');
  await speed.fill('6');
  await expect(sheet.getByText('1.5×', { exact: true }).filter({ visible: true })).toHaveCount(1);
  await page.keyboard.press('Escape');
  await press(page, 'Read aloud');
  await expect.poll(async () => (await audio(page)).rate).toBe(1.5);
  await press(page, 'Read aloud');
  await reload(page);
  await expect(bookPage(page)).toBeVisible();
  await openSettings(page);
  await expect(dialog(page, 'Typography and theme').getByRole('slider', { name: 'Narration speed' })).toHaveValue('6');
  await page.keyboard.press('Escape');
  await press(page, 'Read aloud');
  await expect.poll(async () => (await audio(page)).rate).toBe(1.5);
  expect(errors).toEqual([]);
});

test('page numbers are passed over, unless the reader asks for them; a table can be left', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, structuredBook('Structured'));
  await watchMarks(page);
  await press(page, 'Read aloud');
  await expect.poll(() => marked(page), FAST).toBe('Cell one');
  // inside the table, it can be left
  await press(page, 'Skip table');
  // nothing between: the page number passed over, the table left. Polled
  // on what the page recorded, not on the mark itself: the recorder samples
  // every 20 ms, so it can lag a mark the test has already seen, and the
  // last phrase's mark goes when the chapter ends
  await expect.poll(() => seen(page), FAST).toEqual(['First words.', 'Second words.', 'Cell one', 'After the table.']);
  // the chapter's end, with no chapter after it, stops the narration
  await expect(readAloud(page)).toHaveAttribute('aria-pressed', 'false');
  await expect(control(page, 'Skip table')).toBeHidden();
  // read: the page number is read too
  await openSettings(page);
  const group = dialog(page, 'Typography and theme').getByRole('group', { name: 'Page numbers and notes' });
  await expect(group.getByRole('button', { name: 'Skip' })).toHaveAttribute('aria-pressed', 'true');
  await group.getByRole('button', { name: 'Read' }).click();
  await expect(group.getByRole('button', { name: 'Read' })).toHaveAttribute('aria-pressed', 'true');
  await page.keyboard.press('Escape');
  await page.keyboard.press('Home');
  await watchMarks(page);
  await press(page, 'Read aloud');
  await expect.poll(() => seen(page), FAST).toEqual(['First words.', 'Page 2', 'Second words.', 'Cell one']);
  expect(errors).toEqual([]);
});

test('a book without overlays offers reading aloud by speech, and no narration', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, { title: 'Unvoiced', author: 'Narration Tests', rawChapters: [{ body: '<p id="a">Nothing recorded.</p>' }] });
  await expect(async () => {
    if (!(await control(page, 'Previous page').isVisible())) await page.keyboard.press('t');
    await expect(readAloud(page)).toBeVisible({ timeout: 1000 });
  }).toPass({ timeout: 20000 });
  await expect(control(page, 'Previous phrase')).toBeHidden();
  await expect(control(page, 'Next phrase')).toBeHidden();
  await openSettings(page);
  await expect(dialog(page, 'Typography and theme').getByRole('slider', { name: 'Narration speed' })).toBeHidden();
  await expect(dialog(page, 'Typography and theme').getByRole('group', { name: 'Page numbers and notes' })).toBeHidden();
  expect(errors).toEqual([]);
});

test('a narration whose audio is deflated in the book plays', async ({ page }) => {
  const errors = await start(page);
  await readBook(page, turningBook('Deflated', false));
  await watchMarks(page);
  await press(page, 'Read aloud');
  await expect(readAloud(page)).toHaveAttribute('aria-pressed', 'true');
  await expect.poll(async () => (await audio(page)).time).toBeGreaterThan(0);
  await expect.poll(() => seen(page)).toContain('Paragraph two is read next.');
  expect((await seen(page)).slice(0, 2)).toEqual(['Paragraph one is read first.', 'Paragraph two is read next.']);
  expect(errors).toEqual([]);
});
