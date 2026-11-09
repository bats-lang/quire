/* true when the page saw a click on every button smoke-tap-points.js named, else the names it missed (android-smoke, pwa#205) */
(() => {
  const s = window.__smokeTap;
  if (!s) return 'smoke-tap-points.js did not run';
  const missed = s.expected.filter(id => !s.clicked[id]).concat(s.unmeasured);
  return missed.length === 0 ? 'true' : missed.join(' ');
})()
