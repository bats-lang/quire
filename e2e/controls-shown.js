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
 * - insetsShort: every control keeps the spacing scale's least inset
 *   from the edges of the container it is drawn in (#331).
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

/** The visible controls on the screen shown that come nearer an edge of
    their container than the spacing scale's least inset (#331): the
    page gives the inset as --space-inset, from style.bats's scale. A
    control's container is its nearest ancestor drawn as a surface of its
    own (a ground other than the one behind it, a border all round, or a
    shadow);
    a control in none is in the window, which the screens' own paddings
    keep it from. The gap is measured from the container's padding box
    (inside its border) to what the control draws: its box when the box
    shows (a ground of its own, a border all round, a shadow), else its content
    (an icon button's glyph, a menu item's text). Across a container
    that scrolls that way only its other sides count, and a control
    scrolled out of it is not measured. The book's own page, and the
    turn's copy of it, are left out. Each is named, with its gap and its
    container */
export async function insetsShort(page) {
  return page.evaluate(() => {
    const least = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--space-inset'));
    if (!(least > 0)) return ['the page gives no --space-inset'];
    const controls = 'button, a[href], select, textarea, input:not([type=hidden]):not([type=file]), [role=button], [role=menuitem], [role=tab], [role=switch], [role=slider]';
    const book = document.querySelector('[role=document]');
    const shown = e => e.checkVisibility({ visibilityProperty: true, opacityProperty: true }) && e.getClientRects().length > 0;
    const named = e => (e.getAttribute('aria-label') || e.textContent || e.id || e.tagName).trim().slice(0, 40);
    const painted = colour => colour && colour !== 'transparent' && !/rgba\(.*,\s*0\)$/.test(colour);
    const ground = e => {
      for (let a = e; a; a = a.parentElement) {
        const colour = getComputedStyle(a).backgroundColor;
        if (painted(colour)) return colour;
      }
      return 'none';
    };
    // a box drawn round it: a border on every side (a divider under a
    // bar is a line, not a box)
    const edged = style => ['Top', 'Right', 'Bottom', 'Left'].every(side =>
      parseFloat(style[`border${side}Width`]) > 0 && style[`border${side}Style`] !== 'none' && painted(style[`border${side}Color`]));
    // drawn as a surface of its own: a ground unlike the one behind it,
    // a box or a shadow
    const surface = e => {
      const style = getComputedStyle(e);
      if (edged(style) || style.boxShadow !== 'none') return true;
      return painted(style.backgroundColor) && style.backgroundColor !== ground(e.parentElement);
    };
    const bad = [];
    for (const control of document.querySelectorAll(controls)) {
      if (book && book.contains(control)) continue;
      if (control.closest('[inert]')) continue;
      if (!shown(control)) continue;
      const own = control.getBoundingClientRect();
      // read out, not shown (1 px and clipped)
      if (own.width <= 1 && own.height <= 1) continue;
      let container = control.parentElement;
      while (container && container !== document.body && !surface(container)) container = container.parentElement;
      if (!container || container === document.body || container === document.documentElement) continue;
      const box = container.getBoundingClientRect();
      const style = getComputedStyle(container);
      const inner = {
        left: box.left + parseFloat(style.borderLeftWidth), right: box.right - parseFloat(style.borderRightWidth),
        top: box.top + parseFloat(style.borderTopWidth), bottom: box.bottom - parseFloat(style.borderBottomWidth),
      };
      let drawn = own;
      if (!surface(control)) {
        const range = document.createRange();
        range.selectNodeContents(control);
        const content = range.getBoundingClientRect();
        if (content.width > 0 && content.height > 0) drawn = content;
      }
      // a scroller between them (or the container itself) scrolls that way
      let across = false, down = false;
      for (let a = control.parentElement; a; a = a.parentElement) {
        const s = getComputedStyle(a);
        if (/auto|scroll/.test(s.overflowX) && a.scrollWidth > a.clientWidth + 1) across = true;
        if (/auto|scroll/.test(s.overflowY) && a.scrollHeight > a.clientHeight + 1) down = true;
        if (a === container) break;
      }
      if (down && (own.bottom <= inner.top || own.top >= inner.bottom)) continue;
      if (across && (own.right <= inner.left || own.left >= inner.right)) continue;
      const gaps = [];
      if (!across) gaps.push(['left', drawn.left - inner.left], ['right', inner.right - drawn.right]);
      if (!down) gaps.push(['top', drawn.top - inner.top], ['bottom', inner.bottom - drawn.bottom]);
      const short = gaps.filter(([, gap]) => gap < least - 0.5);
      if (short.length) {
        const where = container.id || container.className || container.tagName;
        bad.push(`${named(control)}: ${short.map(([side, gap]) => `${side} ${Math.round(gap)} px`).join(', ')} from ${where}`);
      }
    }
    return bad;
  });
}
