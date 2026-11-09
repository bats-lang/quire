/* the centre of a word of the first page, in device pixels: x and y (android-smoke, pwa#205); a word in the page's middle third, clear of the turn zones and the footer, so a long press on it is no tap */
(() => {
  const page = document.getElementById('page');
  if (!page) return 'no page';
  const box = page.getBoundingClientRect();
  const walker = document.createTreeWalker(page, NodeFilter.SHOW_TEXT);
  const middle = { x: box.left + box.width / 2, y: box.top + box.height / 2 };
  let best = null;
  for (let t; (t = walker.nextNode());) {
    if (t.parentElement.closest('a, rt, rp')) continue;
    for (const m of t.data.matchAll(/\S{4,}/g)) {
      const range = document.createRange();
      range.setStart(t, m.index);
      range.setEnd(t, m.index + m[0].length);
      const b = range.getClientRects()[0];
      if (!b) continue;
      const x = b.left + b.width / 2;
      const y = b.top + b.height / 2;
      /* the word's centre in the page's middle three fifths (a large font scale makes a word wider than the middle third), clear of the footer and the top */
      if (x < box.left + box.width * 0.2 || x > box.left + box.width * 0.8) continue;
      if (y < box.top + 150 || y > box.bottom - 140) continue;
      if (b.left < box.left || b.right > box.right) continue;
      const d = Math.hypot(x - middle.x, y - middle.y);
      if (!best || d < best.d) best = { x, y, d };
    }
  }
  if (!best) return 'no word';
  return Math.round(best.x * devicePixelRatio) + ' ' + Math.round(best.y * devicePixelRatio);
})()
