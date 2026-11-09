/* opens the book when the library is showing: a click on the first card (android-smoke, pwa#267); the book the smoke test hands the app is already open then */
(() => {
  const page = document.getElementById('page');
  if (page && page.getBoundingClientRect().width > 0) return 'open';
  const card = document.querySelector('[role=region] [role=group]');
  if (!card) return 'no card';
  const b = card.getBoundingClientRect();
  const target = document.elementFromPoint(b.left + b.width / 2, b.top + b.height / 2);
  if (!target) return 'no target';
  target.click();
  return 'opened';
})()
