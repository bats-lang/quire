/* true once the open book's first page is laid out: words of it are on the screen (android-smoke, pwa#267) */
(() => {
  const page = document.getElementById('page');
  if (!page) return 'no page';
  const box = page.getBoundingClientRect();
  if (box.width === 0 || box.height === 0) return 'page has no size';
  const walker = document.createTreeWalker(page, NodeFilter.SHOW_TEXT);
  let words = 0;
  for (let t; (t = walker.nextNode());) {
    for (const m of t.data.matchAll(/\S{4,}/g)) {
      const range = document.createRange();
      range.setStart(t, m.index);
      range.setEnd(t, m.index + m[0].length);
      const b = range.getClientRects()[0];
      if (b && b.left >= box.left && b.right <= box.right && b.top >= box.top && b.bottom <= box.bottom) words += 1;
    }
  }
  return words >= 4 ? 'true' : 'words on the page: ' + words;
})()
