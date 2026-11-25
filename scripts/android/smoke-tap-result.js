/* true when every button smoke-tap-points.js named got a click, else the names missed (pwa#205) */
(() => {
  const s = window.__smokeTap;
  if (!s) return 'smoke-tap-points.js did not run';
  const missed = s.expected.filter(id => !s.clicked[id]).concat(s.unmeasured);
  return missed.length === 0 ? 'true' : missed.join(' ');
})()
