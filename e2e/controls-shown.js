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
 * - textContrastShort: a placeholder reads at 4.5:1 against its field
 *   (WCAG 1.4.3), in whatever theme is shown (quire#357). Every other
 *   text colour is written through the stylesheet's proven pairs.
 * - stateCueShort: a chosen tab is told apart by more than a tint
 *   (WCAG 1.4.11): an underline, a border or a bolder weight that the
 *   others do not have (quire#358).
 * - onOffPairs: a setting with two states is a switch (Material 3: a
 *   switch makes a binary selection, its effect immediate), never a
 *   segmented On | Off, nor a lone button pressed on and off (quire#363).
 * - labelsShown: every visible sign-in field is named by a visible label
 *   (a <label for>) that reads at 4.5:1, not by a placeholder that
 *   vanishes as it is typed in (WCAG 3.3.2, 1.3.1; quire#361).
 * - labelInName: a button's accessible name holds the words it shows
 *   (WCAG 2.5.3), so a glyph drawn into its text is not part of it.
 * - insetsShort: every control keeps the spacing scale's least inset
 *   from the edges of the container it is drawn in (#331).
 * - inSafeArea: no control or text comes within the spacing scale's
 *   least inset of the screen's safe-area insets, where the system's
 *   bars are drawn over the page (#341).
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

/** The visible fields on the screen shown whose placeholder is under
    4.5:1 against the field's ground, as the page draws it (the colour
    with its opacity over the field's background). Each is named, with
    the ratio */
export async function textContrastShort(page) {
  return page.evaluate(() => {
    const shown = e => e.checkVisibility({ visibilityProperty: true, opacityProperty: true }) && e.getClientRects().length > 0;
    const parse = css => {
      const m = css.match(/rgba?\(([^)]+)\)/);
      if (!m) return null;
      const [r, g, b, a = 1] = m[1].split(/[ ,\/]+/).filter(Boolean).map(Number);
      return { r, g, b, a };
    };
    const over = (top, under) => ({
      r: top.r * top.a + under.r * (1 - top.a), g: top.g * top.a + under.g * (1 - top.a), b: top.b * top.a + under.b * (1 - top.a), a: 1,
    });
    const light = c => {
      const f = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
      return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    };
    const ground = e => {
      let under = { r: 255, g: 255, b: 255, a: 1 };
      const chain = [];
      for (let a = e; a; a = a.parentElement) chain.push(parse(getComputedStyle(a).backgroundColor));
      for (const c of chain.reverse()) if (c && c.a > 0) under = over(c, under);
      return under;
    };
    const bad = [];
    for (const e of document.querySelectorAll('input[placeholder],textarea[placeholder]')) {
      if (!shown(e) || e.value) continue;
      const style = getComputedStyle(e, '::placeholder');
      const text = parse(style.color);
      if (!text) continue;
      const back = ground(e);
      const drawn = over({ ...text, a: text.a * parseFloat(style.opacity || '1') }, back);
      const [hi, lo] = [light(drawn), light(back)].sort((x, y) => y - x);
      const ratio = (hi + 0.05) / (lo + 0.05);
      if (ratio < 4.5) bad.push(`${e.getAttribute('aria-label') || e.id || e.placeholder}: ${ratio.toFixed(2)}:1`);
    }
    return bad;
  });
}

/** The visible tabs on the screen shown whose chosen one has no cue
    beside its ground: an inset shadow, a border, an underline or a
    weight the other tabs of its list do not have. Each list is named */
export async function stateCueShort(page) {
  return page.evaluate(() => {
    const shown = e => e.checkVisibility({ visibilityProperty: true, opacityProperty: true }) && e.getClientRects().length > 0;
    const cue = e => {
      const style = getComputedStyle(e);
      return [style.boxShadow, style.textDecorationLine, style.fontWeight, style.borderBottomWidth, style.outlineStyle].join('|');
    };
    const bad = [];
    for (const list of document.querySelectorAll('[role=tablist]')) {
      if (!shown(list)) continue;
      const tabs = [...list.querySelectorAll('[role=tab]')].filter(shown);
      const chosen = tabs.filter(t => t.getAttribute('aria-selected') === 'true');
      const others = tabs.filter(t => t.getAttribute('aria-selected') !== 'true');
      if (!chosen.length || !others.length) continue;
      if (others.every(o => cue(o) === cue(chosen[0]))) bad.push(list.getAttribute('aria-label') || list.id);
    }
    return bad;
  });
}

/** The visible two-state settings on the screen shown that are not
    switches: a segmented group (.seg) whose buttons are exactly On and
    Off, and a .seg holding one button that is pressed on and off.
    Each is named */
export async function onOffPairs(page) {
  return page.evaluate(() => {
    const shown = e => e.checkVisibility({ visibilityProperty: true, opacityProperty: true }) && e.getClientRects().length > 0;
    const bad = [];
    // (.cseg is the collections' chips, which are a list that has one chip at times, not a setting)
    for (const group of document.querySelectorAll('.seg:not(.cseg)')) {
      if (!shown(group)) continue;
      const buttons = [...group.querySelectorAll('button')].filter(shown);
      const names = buttons.map(b => b.textContent.trim()).sort();
      const named = (group.getAttribute('aria-label') || group.id).trim();
      if (names.length === 2 && names[0] === 'Off' && names[1] === 'On') bad.push(`${named}: On | Off`);
      if (buttons.length === 1 && buttons[0].hasAttribute('aria-pressed') && !buttons[0].classList.contains('switch')) bad.push(`${named}: one pressed button`);
    }
    return bad;
  });
}

/** The visible sign-in fields (url, user name and password inputs) on
    the screen shown with no visible label of their own, or with one
    under 4.5:1 against its ground. Each is named */
export async function labelsShown(page) {
  return page.evaluate(() => {
    const shown = e => e.checkVisibility({ visibilityProperty: true, opacityProperty: true }) && e.getClientRects().length > 0;
    const parse = css => {
      const m = css.match(/rgba?\(([^)]+)\)/);
      if (!m) return null;
      const [r, g, b, a = 1] = m[1].split(/[ ,\/]+/).filter(Boolean).map(Number);
      return { r, g, b, a };
    };
    const over = (top, under) => ({
      r: top.r * top.a + under.r * (1 - top.a), g: top.g * top.a + under.g * (1 - top.a), b: top.b * top.a + under.b * (1 - top.a), a: 1,
    });
    const light = c => {
      const f = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
      return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    };
    const ground = e => {
      let under = { r: 255, g: 255, b: 255, a: 1 };
      const chain = [];
      for (let a = e; a; a = a.parentElement) chain.push(parse(getComputedStyle(a).backgroundColor));
      for (const c of chain.reverse()) if (c && c.a > 0) under = over(c, under);
      return under;
    };
    const bad = [];
    for (const input of document.querySelectorAll('input[type=url],input[type=password],input[type=text]')) {
      if (!shown(input)) continue;
      const labels = [...(input.labels || [])].filter(shown);
      const name = input.getAttribute('aria-label') || input.id;
      if (!labels.length) { bad.push(`${name}: no visible label`); continue; }
      const text = parse(getComputedStyle(labels[0]).color);
      const back = ground(labels[0]);
      const [hi, lo] = [light(over(text, back)), light(back)].sort((x, y) => y - x);
      const ratio = (hi + 0.05) / (lo + 0.05);
      if (ratio < 4.5) bad.push(`${name}: its label reads at ${ratio.toFixed(2)}:1`);
    }
    return bad;
  });
}

/** The visible buttons on the screen shown whose accessible name does
    not hold the words they show (WCAG 2.5.3): one that carries an
    aria-label without its visible text, and one whose text has a drawn
    glyph in it (the chevron a row ends in is the stylesheet's, with an
    empty alternative, never a character of the name). Each is named */
export async function labelInName(page) {
  return page.evaluate(() => {
    const shown = e => e.checkVisibility({ visibilityProperty: true, opacityProperty: true }) && e.getClientRects().length > 0;
    const bad = [];
    for (const button of document.querySelectorAll('button')) {
      if (!shown(button)) continue;
      // (an icon button's text is its glyph, in the Private Use Area: its name is its label alone)
      const text = button.textContent.replace(/[\uE000-\uF8FF]/g, '').replace(/\s+/g, ' ').trim();
      if (!text) continue;
      const label = button.getAttribute('aria-label');
      if (label && !label.toLowerCase().includes(text.toLowerCase())) bad.push(`${text.slice(0, 40)} (named ${label.slice(0, 40)})`);
      if (/[\u203A\u00BB\u2192]/.test(text)) bad.push(`${text.slice(0, 40)} (a glyph in its name)`);
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

/** The visible controls and text on the screen shown that reach into
    the screen's insets (the system's bars: insets, in CSS px, as given
    to the page's env(safe-area-inset-*)) or within the spacing scale's
    least inset (--space-inset) of them (#341). Each is measured as far
    as it shows: cut to every box between it and the window that clips
    it, and only where it is on top (a veil or a panel over it hides
    it). The book's own page is left out: checkPageMargins measures its
    text. Each is named, with the sides it reaches */
export async function inSafeArea(page, insets) {
  return page.evaluate(insets => {
    const least = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--space-inset'));
    if (!(least > 0)) return ['the page gives no --space-inset'];
    const controls = 'button, a[href], select, textarea, input:not([type=hidden]):not([type=file]), [role=button], [role=menuitem], [role=tab], [role=switch], [role=slider]';
    const book = document.querySelector('[role=document]');
    const shown = e => e.checkVisibility({ visibilityProperty: true, opacityProperty: true }) && e.getClientRects().length > 0;
    const named = e => (e.getAttribute('aria-label') || e.textContent || e.id || e.tagName).trim().slice(0, 40);
    const clear = {
      top: insets.top + least, left: insets.left + least,
      right: innerWidth - insets.right - least, bottom: innerHeight - insets.bottom - least,
    };
    // the part of a box that shows: cut to each ancestor that clips
    const seen = (r, e) => {
      let box = { left: r.left, top: r.top, right: r.right, bottom: r.bottom };
      const cut = c => { box = { left: Math.max(box.left, c.left), top: Math.max(box.top, c.top), right: Math.min(box.right, c.right), bottom: Math.min(box.bottom, c.bottom) }; };
      for (let a = e; a && a !== document.documentElement; a = a.parentElement) {
        const s = getComputedStyle(a);
        if (s.overflowX !== 'visible' || s.overflowY !== 'visible') cut(a.getBoundingClientRect());
      }
      cut({ left: 0, top: 0, right: innerWidth, bottom: innerHeight });
      const width = box.right - box.left, height = box.bottom - box.top;
      // (read out, not shown: 1 px and clipped)
      return width > 0.5 && height > 0.5 && (width > 1 || height > 1) ? box : null;
    };
    // the sides of the clear area a shown box reaches past, each where
    // the thing measured is on top
    const reaches = (box, owner) => {
      const bands = {
        top: { ...box, bottom: Math.min(box.bottom, clear.top) },
        bottom: { ...box, top: Math.max(box.top, clear.bottom) },
        left: { ...box, right: Math.min(box.right, clear.left) },
        right: { ...box, left: Math.max(box.left, clear.right) },
      };
      return Object.entries(bands).filter(([, b]) => {
        if (b.right - b.left <= 0.5 || b.bottom - b.top <= 0.5) return false;
        const hit = document.elementFromPoint((b.left + b.right) / 2, (b.top + b.bottom) / 2);
        return hit && owner.contains(hit);
      }).map(([side]) => side);
    };
    // what is drawn through (pointer-events: none) is hit too
    const through = document.createElement('style');
    through.textContent = '*{pointer-events:auto !important}';
    document.head.append(through);
    const bad = [];
    try {
      for (const control of document.querySelectorAll(controls)) {
        if (book && book.contains(control)) continue;
        if (control.closest('[inert]') || !shown(control)) continue;
        const r = control.getBoundingClientRect();
        if (r.width <= 1 && r.height <= 1) continue;
        const box = seen(r, control.parentElement);
        if (!box) continue;
        const sides = reaches(box, control);
        if (sides.length) bad.push(`${named(control)}: ${sides.join(', ')}`);
      }
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      for (let text = walker.nextNode(); text; text = walker.nextNode()) {
        const owner = text.parentElement;
        if (!owner || !text.textContent.trim()) continue;
        if (book && book.contains(owner)) continue;
        if (owner.closest('[inert]') || owner.closest(controls) || !shown(owner)) continue;
        const range = document.createRange();
        range.selectNodeContents(text);
        for (const r of range.getClientRects()) {
          if (r.width <= 1 && r.height <= 1) continue;
          const box = seen(r, owner);
          if (!box) continue;
          const sides = reaches(box, owner);
          if (sides.length) { bad.push(`"${text.textContent.trim().slice(0, 40)}": ${sides.join(', ')}`); break; }
        }
      }
    } finally {
      through.remove();
    }
    return bad;
  }, insets);
}
