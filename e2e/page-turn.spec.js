// The page turn, animated (#246): the page being left lies over the
// page and slides off, the incoming page beneath it, by a tap, a key, a
// button and a drag, on and back, into the next chapter too; a drag's
// page follows the finger. Where the system asks for less motion, a
// turn is instant. Every turn ends on the right page, in every project.
//
// The page being left is a copy of the page, shown only while the page
// turns: so while it turns, the page's text is there twice (the copy is
// hidden from assistive technology, and found here by its text alone).

import { test, expect } from '@playwright/test';
import { start, readBook, place, bookPage, chapters, clickControl } from './helpers.js';

const book = (title, rtl = false) => ({ title, author: 'Turn Tests', rawChapters: chapters(2, 20), rtl });

// Whether an element is seen (in the page's code below: not hidden, nor
// in a hidden box): the page's paragraphs always are, wherever its
// columns put them; the copy only while it lies over the page
// How many times the first paragraph's text is seen: the page's, and
// the copy's while the page turns away from it (the copy is kept, hidden,
// between turns)
const copies = (page, text = 'Para 1.0 ') => page.evaluate(([text]) => {
  const visible = (el) => el.checkVisibility({ visibilityProperty: true });
  return [...document.querySelectorAll('p')].filter(p => p.textContent.startsWith(text) && visible(p)).length;
}, [text]);

// Where the copy of the first paragraph is across the screen, frame by
// frame, until the copy is gone: how the page being left moves
// (waiting up to a second for it to come)
const slide = page => page.evaluate(() => new Promise((resolve) => {
  const visible = (el) => el.checkVisibility({ visibilityProperty: true });
  const seenAt = [];
  let waited = 0;
  const step = () => {
    const found = [...document.querySelectorAll('[aria-hidden="true"] p')]
      .find(p => p.textContent.startsWith('Para 1.0 ') && visible(p));
    if (found) seenAt.push(found.getBoundingClientRect().left);
    else if (seenAt.length > 0 || waited++ > 60) { resolve(seenAt); return; }
    requestAnimationFrame(step);
  };
  step();
}));

const sides = async (page) => {
  const box = await bookPage(page).boundingBox();
  return { y: box.y + box.height / 2, left: box.x + 10, right: box.x + box.width - 10, mid: box.x + box.width / 2 };
};

// A drag of touch pointer events, as the gestures recognizer gets them
const drag = (page, x0, x1, y, { cancel = false, id = 31 } = {}) =>
  bookPage(page).evaluate(async (el, [x0, x1, y, cancel, id]) => {
    const ev = (type, x) => el.dispatchEvent(new PointerEvent(type, {
      bubbles: true, pointerId: id, pointerType: 'touch', isPrimary: true, clientX: x, clientY: y,
    }));
    const wait = (t) => new Promise((r) => setTimeout(r, t));
    ev('pointerdown', x0);
    for (let i = 1; i <= 4; i++) { await wait(16); ev('pointermove', x0 + ((x1 - x0) * i) / 4); }
    await wait(16);
    ev(cancel ? 'pointercancel' : 'pointerup', x1);
  }, [x0, x1, y, cancel, id]);

// What a turn looked like: the page shown at its end, and whether the
// page being left was laid over it on the way (the copy seen in any
// frame of the turn, however short the turn)
async function turn(page, act) {
  await expect.poll(() => copies(page)).toBe(1);
  await page.evaluate(() => {
    const visible = (el) => el.checkVisibility({ visibilityProperty: true });
    window.turnLaid = false;
    window.turnWatching = true;
    const step = () => {
      if ([...document.querySelectorAll('[aria-hidden="true"] p')].some(visible)) window.turnLaid = true;
      if (window.turnWatching) requestAnimationFrame(step);
    };
    step();
  });
  await act();
  await expect.poll(() => copies(page)).toBe(1);
  const laid = await page.evaluate(() => { window.turnWatching = false; return window.turnLaid; });
  return { laid, at: (await place(page)).p };
}

test.describe('a page turn', () => {
  test('by a key, a tap and a button, on and back, slides the page being left off over the incoming one', async ({ page }) => {
    await start(page);
    await readBook(page, book('Keys and Taps'));
    const { y, left, right } = await sides(page);
    expect(await turn(page, () => page.keyboard.press('ArrowRight'))).toEqual({ laid: true, at: 2 });
    expect(await turn(page, () => page.keyboard.press('ArrowLeft'))).toEqual({ laid: true, at: 1 });
    expect(await turn(page, () => page.mouse.click(right, y))).toEqual({ laid: true, at: 2 });
    expect(await turn(page, () => page.mouse.click(left, y))).toEqual({ laid: true, at: 1 });
    expect(await turn(page, () => clickControl(page, 'Next page'))).toEqual({ laid: true, at: 2 });
    expect(await turn(page, () => clickControl(page, 'Previous page'))).toEqual({ laid: true, at: 1 });
  });

  test('on goes to the left, and back to the right, the page following its turn to its end', async ({ page }) => {
    await start(page);
    await readBook(page, book('Slides'));
    // on: the page being left (the first) goes off to the left
    const sliding = slide(page);
    await page.keyboard.press('ArrowRight');
    const on = await sliding;
    expect(on.length).toBeGreaterThan(2);
    for (let i = 1; i < on.length; i++) expect(on[i]).toBeLessThanOrEqual(on[i - 1]);
    expect(on[on.length - 1]).toBeLessThan(on[0]);
    await expect.poll(async () => (await place(page)).p).toBe(2);
    expect(await copies(page)).toBe(1);
  });

  test('right to left, a key turning on slides the page off to the right', async ({ page }) => {
    await start(page);
    await readBook(page, book('Leftward Slides', true));
    const sliding = slide(page);
    await page.keyboard.press('ArrowLeft');
    const on = await sliding;
    expect(on.length).toBeGreaterThan(2);
    expect(on[on.length - 1]).toBeGreaterThan(on[0]);
    await expect.poll(async () => (await place(page)).p).toBe(2);
  });

  test('into the next chapter and back, the page being left lies over the chapter coming in', async ({ page }) => {
    await start(page);
    await readBook(page, book('Chapters'));
    await page.keyboard.press('End');
    await expect.poll(async () => { const p = await place(page); return p.p === p.t; }).toBe(true);
    await expect.poll(() => copies(page)).toBe(1);
    await page.keyboard.press('ArrowRight');
    // the copy of chapter 1's last page, over chapter 2's first
    await expect.poll(async () => (await place(page)).ch).toBe(2);
    await expect.poll(() => copies(page)).toBe(0);
    expect((await place(page)).p).toBe(1);
    await page.keyboard.press('ArrowLeft');
    await expect.poll(async () => (await place(page)).ch).toBe(1);
    const back = await place(page);
    expect(back.p).toBe(back.t);
    await expect.poll(() => copies(page, 'Para 2.0 ')).toBe(0);
  });
});

// Less motion, as the system asks for it (Playwright's reducedMotion
// option is the context's; emulated here on the page itself)
const lessMotion = ({ page }) => page.emulateMedia({ reducedMotion: 'reduce' });

// How long, in ms, from a key's press to the first frame drawn after it
// (the first frame of the turn it starts): watched from before the
// press, then read once the frame has come
const watchFirstFrame = (page) => page.evaluate(() => {
  window.firstFrame = new Promise((resolve) => {
    const onKey = () => {
      window.removeEventListener('keydown', onKey, true);
      const pressed = performance.now();
      requestAnimationFrame(() => resolve(performance.now() - pressed));
    };
    window.addEventListener('keydown', onKey, true);
  });
});
const firstFrame = (page) => page.evaluate(() => window.firstFrame);

test.describe('a page turn on a long chapter', () => {
  // The copy is kept between turns, so a turn only scrolls it and shows
  // it: its first frame comes as soon as a turn without the copy's. On a
  // chapter of about 300 KB, making the copy at the turn took 110 to 200
  // ms here, the kept copy 20 to 30, and a turn with no copy 11 to 24
  test('starts within 50 ms of the key, half the turns or more', async ({ page }) => {
    await start(page);
    await readBook(page, { title: 'A Long Chapter', author: 'Turn Tests', rawChapters: chapters(2, 900) });
    // the copy, made a moment after the chapter is shown, kept hidden
    await expect.poll(() => page.locator('[aria-hidden="true"] p').count()).toBeGreaterThan(0);
    const times = [];
    for (let i = 0; i < 6; i++) {
      await watchFirstFrame(page);
      await page.keyboard.press(i % 2 ? 'ArrowLeft' : 'ArrowRight');
      times.push(await firstFrame(page));
      await expect.poll(async () => (await place(page)).p).toBe(i % 2 ? 1 : 2);
      await expect.poll(() => copies(page)).toBe(1);
    }
    times.sort((a, b) => a - b);
    expect(times[2], `first frames: ${times.map(Math.round).join(', ')} ms`).toBeLessThanOrEqual(50);
  });
});

test.describe('with less motion', () => {
  test.beforeEach(lessMotion);

  test('a turn by a key, a tap or a button is instant: no page is laid over the page', async ({ page }) => {
    await start(page);
    await readBook(page, book('Still Keys'));
    const { y, left, right } = await sides(page);
    expect(await turn(page, () => page.keyboard.press('ArrowRight'))).toEqual({ laid: false, at: 2 });
    expect(await turn(page, () => page.keyboard.press('ArrowLeft'))).toEqual({ laid: false, at: 1 });
    expect(await turn(page, () => page.mouse.click(right, y))).toEqual({ laid: false, at: 2 });
    expect(await turn(page, () => page.mouse.click(left, y))).toEqual({ laid: false, at: 1 });
    expect(await turn(page, () => clickControl(page, 'Next page'))).toEqual({ laid: false, at: 2 });
    expect(await turn(page, () => clickControl(page, 'Previous page'))).toEqual({ laid: false, at: 1 });
  });
});

test.describe('on a touch screen', () => {
  test.use({ hasTouch: true });

  test('a drag turns on and back, the page being left following the finger, and a cancelled one goes back', async ({ page }) => {
    await start(page);
    await readBook(page, book('Dragged Turns'));
    const { y, mid } = await sides(page);
    // a flick to the left: on, from where the finger let go
    expect(await turn(page, () => drag(page, mid + 60, mid - 60, y))).toEqual({ laid: true, at: 2 });
    // to the right: back
    expect(await turn(page, () => drag(page, mid - 60, mid + 60, y))).toEqual({ laid: true, at: 1 });
    // cancelled by the system mid-drag: the page goes back
    expect((await turn(page, () => drag(page, mid + 100, mid - 100, y, { cancel: true }))).at).toBe(1);
  });

  test('held part way, the copy of the page is where the finger took it', async ({ page }) => {
    await start(page);
    await readBook(page, book('Held Turn'));
    const { y, mid } = await sides(page);
    const moved = await bookPage(page).evaluate(async (el, [mid, y]) => {
      const ev = (type, x) => el.dispatchEvent(new PointerEvent(type, {
        bubbles: true, pointerId: 33, pointerType: 'touch', isPrimary: true, clientX: x, clientY: y,
      }));
      const frame = () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
      const copy = () => [...document.querySelectorAll('[aria-hidden="true"] p')]
        .find(p => p.textContent.startsWith('Para 1.0 ') && p.checkVisibility({ visibilityProperty: true }));
      const page = [...el.querySelectorAll('p')].find(p => p.textContent.startsWith('Para 1.0 '));
      const rest = page.getBoundingClientRect().left;
      ev('pointerdown', mid + 60);
      for (const dx of [20, 40, 60]) { await frame(); ev('pointermove', mid + 60 - dx); }
      await frame(); await frame();
      const held = copy() ? copy().getBoundingClientRect().left : null;
      ev('pointercancel', mid);
      return [rest, held];
    }, [mid, y]);
    // dragged some 60 px to the left (the recognizer's slop taken off)
    expect(moved[1]).not.toBeNull();
    expect(moved[0] - moved[1]).toBeGreaterThan(30);
    await expect.poll(() => copies(page)).toBe(1);
    expect((await place(page)).p).toBe(1);
  });

  test.describe('with less motion', () => {
    test.beforeEach(lessMotion);

    test('a drag still turns on and back, and its page goes at once when let go', async ({ page }) => {
      await start(page);
      await readBook(page, book('Still Drags'));
      const { y, mid } = await sides(page);
      await drag(page, mid + 60, mid - 60, y);
      expect(await copies(page)).toBe(1);
      await expect.poll(async () => (await place(page)).p).toBe(2);
      await drag(page, mid - 60, mid + 60, y);
      expect(await copies(page)).toBe(1);
      await expect.poll(async () => (await place(page)).p).toBe(1);
    });
  });
});
