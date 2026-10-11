// The picture viewer (quire#382): a book's picture, full screen, fitted to
// the screen whatever its size, on a dark ground, and zoomed by a pinch, a
// double tap or the Zoom buttons, and moved by a finger.
//
// Research (written on the issue): Apple Books and Kobo open a picture
// from a double tap and zoom it by pinch and double tap; PhotoSwipe, the
// web's usual viewer, fits the picture, zooms to 2.5 times the fit on a
// double tap and at most 4 times the fit (photoswipe.com/adjusting-zoom-level);
// WCAG 2.5.1 asks for a way to zoom that is not a pinch, which are the
// Zoom buttons.

import { test, expect } from './fixtures.js';
import zlib from 'node:zlib';
import { start, readBook, chapterBody, bookPage, dialog } from './helpers.js';

/** A w by h PNG of one grey */
function png(w, h) {
  const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
  const crc = b => { let c = 0xffffffff; for (const x of b) c = crcTable[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]);
    const c = Buffer.alloc(4); c.writeUInt32BE(crc(td));
    return Buffer.concat([len, td, c]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 0;
  const raw = Buffer.alloc((w + 1) * h, 128);
  for (let y = 0; y < h; y++) raw[y * (w + 1)] = 0;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

/** The viewer open on a 64 by 32 picture of a book (small, as a diagram
    in a book is: the viewer shows it larger than that) */
async function viewerOpen(page) {
  await start(page);
  await readBook(page, {
    title: 'Viewer', author: 'Bot',
    rawChapters: [{ body: '<p><img src="images/p.png" alt="the map"/></p>' + chapterBody(1, 10) }],
    extraEntries: [{ name: 'OEBPS/images/p.png', data: png(64, 32), store: true }],
  });
  await page.keyboard.press('t');
  const pic = bookPage(page).getByRole('img', { name: 'the map' });
  await expect.poll(() => pic.evaluate(i => i.naturalWidth)).toBe(64);
  await pic.dblclick();
  const viewer = dialog(page, 'Image');
  await expect(viewer).toBeVisible();
  await expect.poll(() => viewer.locator('img').evaluate(i => i.complete && i.naturalWidth)).toBe(64);
  return viewer;
}

/** What the viewer shows: the scroller's size, the picture's box as laid
    out, how far it is scrolled and what of the box the picture itself
    covers (object-fit: contain) */
const shown = page => page.evaluate(() => {
  const box = document.getElementById('image-box');
  const image = document.getElementById('image-full');
  const view = box.getBoundingClientRect();
  const laid = image.getBoundingClientRect();
  const fit = Math.min(laid.width / image.naturalWidth, laid.height / image.naturalHeight);
  return {
    viewW: view.width, viewH: view.height,
    boxW: laid.width, boxH: laid.height,
    left: box.scrollLeft, top: box.scrollTop,
    drawnW: image.naturalWidth * fit, drawnH: image.naturalHeight * fit,
  };
});

/** The zoom the picture is at, as the box is larger than the scroller */
const zoomOf = async page => { const s = await shown(page); return s.boxW / s.viewW; };

const close = (a, b, tolerance = 0.05) => Math.abs(a - b) <= tolerance * Math.max(1, Math.abs(b));

test('a picture is fitted to the screen on a dark ground, and not shown at its inline size', async ({ page }) => {
  const viewer = await viewerOpen(page);
  const s = await shown(page);
  // the picture's longer side is at least 90% of the screen's side it fills
  expect(Math.max(s.drawnW / s.viewW, s.drawnH / s.viewH)).toBeGreaterThanOrEqual(0.9);
  // and the whole of it is shown
  expect(s.drawnW).toBeLessThanOrEqual(s.viewW + 1);
  expect(s.drawnH).toBeLessThanOrEqual(s.viewH + 1);
  expect(s.left).toBe(0);
  // the ground is dark, whatever the theme: its luminance is low
  const luminance = await viewer.evaluate(e => {
    const [r, g, b] = getComputedStyle(e).backgroundColor.match(/\d+(\.\d+)?/g).map(Number)
      .map(v => { const c = v / 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  });
  expect(luminance).toBeLessThan(0.1);
});

test('a double tap zooms in where it is made, and a second goes back to the fit', async ({ page }) => {
  const viewer = await viewerOpen(page);
  const before = await shown(page);
  const picture = viewer.locator('img');
  await picture.dblclick();
  await expect.poll(() => zoomOf(page)).toBeCloseTo(2.5, 1);
  const zoomed = await shown(page);
  expect(zoomed.boxW).toBeGreaterThan(before.boxW * 2);
  await picture.dblclick();
  await expect.poll(() => zoomOf(page)).toBeCloseTo(1, 2);
  const again = await shown(page);
  expect(close(again.drawnW, before.drawnW)).toBe(true);
  expect(again.left).toBe(0);
});

test('the Zoom buttons zoom in and out, within the least and the most', async ({ page }) => {
  const viewer = await viewerOpen(page);
  const zoomIn = viewer.getByRole('button', { name: 'Zoom in', exact: true });
  const zoomOut = viewer.getByRole('button', { name: 'Zoom out', exact: true });
  // the least is the fit
  await zoomOut.click();
  expect(await zoomOf(page)).toBeCloseTo(1, 2);
  await zoomIn.click();
  await expect.poll(() => zoomOf(page)).toBeCloseTo(1.5, 1);
  for (let k = 0; k < 8; k++) await zoomIn.click();
  // the most is 4 times the fit
  await expect.poll(() => zoomOf(page)).toBeCloseTo(4, 1);
  await zoomOut.click();
  await expect.poll(() => zoomOf(page)).toBeLessThan(3);
  // a zoom scrolls about the middle: the middle of the picture stays
  const s = await shown(page);
  const middle = (s.left + s.viewW / 2) / s.boxW;
  expect(middle).toBeGreaterThan(0.4);
  expect(middle).toBeLessThan(0.6);
  // closed, and opened again, it is fitted again
  await viewer.getByRole('button', { name: 'Close' }).click();
  await expect(viewer).toBeHidden();
  await bookPage(page).getByRole('img', { name: 'the map' }).dblclick();
  await expect(viewer).toBeVisible();
  await expect.poll(() => zoomOf(page)).toBeCloseTo(1, 2);
});

/** Touch pointer events on the viewer's scroller, as two fingers or one
    make them: each step is a list of [id, x, y] */
const touches = (page, steps) =>
  page.evaluate(async steps => {
    const target = document.getElementById('image-box');
    const wait = ms => new Promise(r => setTimeout(r, ms));
    const down = new Set();
    for (const step of steps) {
      for (const [type, id, x, y] of step) {
        if (type === 'pointerdown') down.add(id);
        target.dispatchEvent(new PointerEvent(type, {
          bubbles: true, pointerId: id, pointerType: 'touch', isPrimary: id === Math.min(...down),
          clientX: x, clientY: y,
        }));
        if (type === 'pointerup' || type === 'pointercancel') down.delete(id);
      }
      await wait(24);
    }
    await wait(80);
  }, steps);

test('a pinch zooms about the fingers\' middle, and the fingers moving together move the picture', async ({ page }) => {
  const viewer = await viewerOpen(page);
  const s = await shown(page);
  const view = await viewer.locator('#image-box').boundingBox();
  const cx = view.x + view.width / 2;
  const cy = view.y + view.height / 2;
  const gap = 40;
  const apart = k => [[
    ['pointermove', 1, cx - gap - k * 10, cy],
    ['pointermove', 2, cx + gap + k * 10, cy],
  ]];
  const steps = [[['pointerdown', 1, cx - gap, cy]], [['pointerdown', 2, cx + gap, cy]]];
  // the fingers draw apart to twice as far, in steps
  for (let k = 1; k <= 4; k++) steps.push(...apart(k));
  await touches(page, steps);
  // 2 times: the distance went from 80 to 160
  await expect.poll(() => zoomOf(page)).toBeGreaterThan(1.7);
  expect(await zoomOf(page)).toBeLessThan(2.3);
  // the middle of the picture is still under the middle of the fingers
  const z = await shown(page);
  expect(close((z.left + s.viewW / 2) / z.boxW, 0.5, 0.1)).toBe(true);
  // let go; then the fingers close to half as far from there: back to the fit
  await touches(page, [[['pointerup', 1, cx - gap - 40, cy]], [['pointerup', 2, cx + gap + 40, cy]]]);
  const fingers = [[['pointerdown', 1, cx - 80, cy]], [['pointerdown', 2, cx + 80, cy]]];
  for (let k = 1; k <= 8; k++) fingers.push([['pointermove', 1, cx - 80 + k * 9, cy], ['pointermove', 2, cx + 80 - k * 9, cy]]);
  await touches(page, fingers);
  await expect.poll(() => zoomOf(page)).toBeLessThan(1.3);
  await touches(page, [[['pointerup', 1, cx - 8, cy]], [['pointerup', 2, cx + 8, cy]]]);
  // the most is held: a pinch past 4 times stays at 4
  const wide = [[['pointerdown', 1, cx - 20, cy]], [['pointerdown', 2, cx + 20, cy]]];
  for (let k = 1; k <= 12; k++) wide.push([['pointermove', 1, cx - 20 - k * 20, cy], ['pointermove', 2, cx + 20 + k * 20, cy]]);
  await touches(page, wide);
  await expect.poll(() => zoomOf(page)).toBeGreaterThan(3.9);
  expect(await zoomOf(page)).toBeLessThanOrEqual(4.01);
});

test('one finger moves a zoomed picture, and moves nothing of a fitted one', async ({ page }) => {
  const viewer = await viewerOpen(page);
  const view = await viewer.locator('#image-box').boundingBox();
  const cx = view.x + view.width / 2;
  const cy = view.y + view.height / 2;
  const drag = (x, y, dx, dy, n = 6) => {
    const steps = [[['pointerdown', 5, x, y]]];
    for (let k = 1; k <= n; k++) steps.push([['pointermove', 5, x + dx * k / n, y + dy * k / n]]);
    steps.push([['pointerup', 5, x + dx, y + dy]]);
    return touches(page, steps);
  };
  // fitted: nothing to move
  await drag(cx, cy, -60, 0);
  expect((await shown(page)).left).toBe(0);
  // zoomed in the middle: the finger going left shows more of the right
  await viewer.locator('img').dblclick();
  await expect.poll(() => zoomOf(page)).toBeCloseTo(2.5, 1);
  const before = await shown(page);
  await drag(cx, cy, -60, 0);
  const after = await shown(page);
  expect(after.left).toBeGreaterThan(before.left + 40);
  // and back, and down as well
  await drag(cx, cy, 60, 30);
  const back = await shown(page);
  expect(back.left).toBeLessThan(after.left - 40);
  // a pan stops at the picture's edge
  await drag(cx, cy, 5000, 0, 10);
  expect((await shown(page)).left).toBe(0);
});

test('the viewer fits the picture again when the window changes size', async ({ page }) => {
  const viewer = await viewerOpen(page);
  await viewer.getByRole('button', { name: 'Zoom in', exact: true }).click();
  await expect.poll(() => zoomOf(page)).toBeGreaterThan(1.4);
  const size = page.viewportSize();
  await page.setViewportSize({ width: size.width - 60, height: size.height - 40 });
  await expect.poll(() => zoomOf(page)).toBeCloseTo(1, 2);
  const s = await shown(page);
  expect(close(s.boxW, s.viewW, 0.02)).toBe(true);
  expect(Math.max(s.drawnW / s.viewW, s.drawnH / s.viewH)).toBeGreaterThanOrEqual(0.9);
});

test('a double tap is instant under reduced motion', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  const viewer = await viewerOpen(page);
  await viewer.locator('img').dblclick();
  // no frame is waited for: the next read already has the zoom
  expect(await zoomOf(page)).toBeCloseTo(2.5, 1);
});
