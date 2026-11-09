/* the centre of a word of the first page, in device pixels: x and y (android-smoke, pwa#205); a word in the page's middle third, clear of the turn zones and the footer, so a long press on it is no tap */
(() => {
  const page = document.getElementById('page');
  if (!page) return 'no page';
  const box = page.getBoundingClientRect();
  const walker = document.createTreeWalker(page, NodeFilter.SHOW_TEXT);
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
      if (b.left < box.left + box.width * 0.3 || b.right > box.left + box.width * 0.7) continue;
      if (y < box.top + 150 || y > box.bottom - 140) continue;
      return Math.round(x * devicePixelRatio) + ' ' + Math.round(y * devicePixelRatio);
    }
  }
  return 'no word';
})()
