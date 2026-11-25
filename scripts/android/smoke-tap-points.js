/* a line <name> <x> <y> for each toolbar button, in device pixels (android-smoke, pwa#205) */
(() => {
  const bar = document.getElementById('selection-toolbar');
  if (!bar || bar.getClientRects().length === 0) return 'the selection toolbar is not shown';
  const sel = getSelection();
  const state = { clicked: {}, expected: [], unmeasured: [], measuring: false, range: sel.rangeCount > 0 ? sel.getRangeAt(0).cloneRange() : null };
  window.__smokeTap = state;
  if (!window.__smokeTapListening) {
    window.__smokeTapListening = true;
    /* a tap ends the selection (Chromium): it is put back so the toolbar stays for the next tap */
    window.addEventListener('selectionchange', e => {
      const s = window.__smokeTap;
      const now = getSelection();
      if (!s || !s.range || now.toString() !== '') return;
      e.stopImmediatePropagation();
      now.removeAllRanges();
      now.addRange(s.range.cloneRange());
    }, true);
    document.addEventListener('click', e => {
      const s = window.__smokeTap;
      const b = e.target.closest && e.target.closest('#selection-toolbar button, #selection-toolbar a');
      if (!s || s.measuring || !b) return;
      s.clicked[b.id] = true;
      if (b.id !== 'selection-more') {
        e.stopImmediatePropagation();
        e.preventDefault();
      }
    }, true);
  }
  const shown = () => [...bar.querySelectorAll('button, a')].filter(b => {
    const r = b.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  });
  const line = b => {
    const r = b.getBoundingClientRect();
    state.expected.push(b.id);
    return b.id + ' ' + Math.round((r.left + r.width / 2) * devicePixelRatio) + ' ' + Math.round((r.top + r.height / 2) * devicePixelRatio);
  };
  const more = document.getElementById('selection-more');
  const first = shown().filter(b => b.id !== 'selection-more');
  const lines = first.map(line);
  if (more) {
    lines.push(line(more));
    state.measuring = true;
    more.click();
    const second = shown().filter(b => b.id !== 'selection-more' && !first.includes(b));
    lines.push(...second.map(line));
    if (second.length === 0) state.unmeasured.push('the-row-behind-More');
    more.click();
    state.measuring = false;
  }
  return lines.join('\n');
})()
