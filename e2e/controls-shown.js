/**
 * What a control shows, checked on whatever screen is shown (#265,
 * quire#300): the layout spec runs these over every screen, sheet and
 * tab, in every project, so a control added to any of them is checked
 * without anyone remembering to.
 *
 * - cutOff: no control's text is cut. A button's or a link's content
 *   wider or taller than its box, text spilling out of its element, and
 *   a select whose chosen option does not fit it (a select clips its
 *   text inside its own box, where scrollWidth cannot see it: the
 *   Brightness select showed "Syste…").
 * - statesUnseen: every toggle shows whether it is on in how it looks,
 *   not only in aria-pressed (WCAG 1.4.1): its look, and its parts',
 *   differ between on and off.
 */

/** What is cut off on the screen shown: each visible control whose
    content is wider or taller than its box (its label clipped, cut by an
    ellipsis, or spilling over its edges), each visible element of text
    whose text spills out of it (an ellipsis that shortens a title on
    purpose is not counted: the title is whole elsewhere), and each
    visible select narrower than its chosen option needs. The book's own
    page is left out: its columns run past it by design */
export async function cutOff(page) {
  return page.evaluate(() => {
    const controls = 'button, a[href], label, [role=button], [role=menuitem], [role=tab], [role=link], [role=switch], [role=checkbox], [role=radio]';
    const book = document.querySelector('[role=document]');
    const shown = e => e.checkVisibility({ visibilityProperty: true, opacityProperty: true }) && e.getClientRects().length > 0;
    const named = e => (e.getAttribute('aria-label') || e.textContent || e.id || e.tagName).trim().slice(0, 40);
    const bad = [];
    for (const e of document.querySelectorAll('body *')) {
      if (book && book.contains(e)) continue;
      if (!shown(e)) continue;
      if (e.matches('select')) {
        // the select as wide as its chosen option alone needs: a copy
        // holding only that option, out of the flow, so no flex or
        // width rule of its row narrows it
        const chosen = e.options[e.selectedIndex];
        if (!chosen) continue;
        const copy = e.cloneNode(false);
        copy.removeAttribute('id');
        copy.append(chosen.cloneNode(true));
        copy.style.cssText = 'position:absolute;visibility:hidden;width:auto;min-width:0;max-width:none;flex:none';
        e.parentElement.append(copy);
        const needs = copy.getBoundingClientRect().width;
        copy.remove();
        const has = e.getBoundingClientRect().width;
        if (needs > has + 1) bad.push(`${named(e)}: "${chosen.text}" needs ${Math.ceil(needs)} px, has ${Math.floor(has)}`);
        continue;
      }
      const style = getComputedStyle(e);
      // what scrolls holds more than it shows by design
      if (/auto|scroll/.test(style.overflowX + style.overflowY)) continue;
      // read out, not shown (1 px and clipped)
      if (e.clientWidth <= 1 && e.clientHeight <= 1) continue;
      const wide = e.scrollWidth > e.clientWidth + 1;
      const tall = e.scrollHeight > e.clientHeight + 1;
      if (e.matches(controls)) {
        if (wide || tall) bad.push(`${named(e)} (${e.clientWidth}x${e.clientHeight} holds ${e.scrollWidth}x${e.scrollHeight})`);
      } else if (wide && style.overflowX === 'visible' && [...e.childNodes].some(n => n.nodeType === 3 && n.textContent.trim())) {
        bad.push(`${named(e)} (text ${e.scrollWidth} px in ${e.clientWidth})`);
      }
    }
    return bad;
  });
}

/** The visible toggles (aria-pressed) on the screen shown that look the
    same pressed and not: for each, its look and its parts' looks are
    read as it is, then with aria-pressed the other way (set and put back
    at once, nothing clicked), and must differ. Each is named */
export async function statesUnseen(page) {
  return page.evaluate(() => {
    const shown = e => e.checkVisibility({ visibilityProperty: true, opacityProperty: true }) && e.getClientRects().length > 0;
    const properties = ['color', 'background-color', 'border-top-color', 'border-left-color', 'border-top-width',
      'box-shadow', 'outline-style', 'font-weight', 'text-decoration-line', 'left', 'right', 'transform', 'opacity'];
    const look = e => [e, ...e.querySelectorAll('*')].map(part => {
      const style = getComputedStyle(part);
      return properties.map(p => style.getPropertyValue(p)).join('|');
    }).join(';');
    const bad = [];
    for (const e of document.querySelectorAll('[aria-pressed]')) {
      if (!shown(e)) continue;
      const was = e.getAttribute('aria-pressed');
      const before = look(e);
      e.setAttribute('aria-pressed', was === 'true' ? 'false' : 'true');
      const after = look(e);
      e.setAttribute('aria-pressed', was);
      if (before === after) bad.push((e.getAttribute('aria-label') || e.textContent || e.id).trim().slice(0, 40));
    }
    return bad;
  });
}
