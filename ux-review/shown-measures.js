/**
 * What the screen shown looks like, measured from the DOM as the e2e
 * suite's controls-shown.js does (#293): meant to run over every screen
 * the walk opens, in every theme, so a text colour the stylesheet's
 * proofs do not cover (a browser's default placeholder), a state shown
 * by too faint a fill, a row cut by a scroller's edge and the share of
 * the window a panel takes are found without anyone looking.
 *
 * - textContrastShort: visible text (and each field's ::placeholder)
 *   under WCAG's 4.5:1 (3:1 for large text), the ground being the
 *   nearest painted ancestors composited.
 * - stateCueShort: a chosen tab or an on toggle whose fill, edge or
 *   underline is under 3:1 against what it is drawn on, and which no
 *   weight or underline separates from the unchosen ones (WCAG 1.4.11).
 * - rowsCutByScroller: a control or a line of text a scroller's edge
 *   cuts through, where the scroller has more beyond it.
 * - panelShare: the share of the window each open dialog or sheet takes.
 */

export async function textContrastShort(page) {
  return page.evaluate(() => {
    const book = document.querySelector('[role=document]');
    const shown = e => e.checkVisibility({ visibilityProperty: true, opacityProperty: true }) && e.getClientRects().length > 0;
    const parse = c => { const m = /rgba?\(([^)]+)\)/.exec(c); if (!m) return [0, 0, 0, 0]; const p = m[1].split(/[ ,\/]+/).filter(Boolean).map(Number); return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1]; };
    const over = (top, below) => { const a = top[3]; return [0, 1, 2].map(i => top[i] * a + below[i] * (1 - a)).concat([1]); };
    const ground = e => {
      const layers = [];
      for (let a = e; a; a = a.parentElement) {
        const c = parse(getComputedStyle(a).backgroundColor);
        if (c[3] > 0) { layers.push(c); if (c[3] >= 1) break; }
      }
      let base = [255, 255, 255, 1];
      for (let i = layers.length - 1; i >= 0; i--) base = over(layers[i], base);
      return base;
    };
    const lin = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
    const lum = c => 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]);
    const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
    const named = e => (e.getAttribute('aria-label') || e.textContent || e.id || e.tagName).trim().replace(/\s+/g, ' ').slice(0, 36);
    const bad = [];
    const check = (e, colour, what, size, weight) => {
      const bg = ground(e), fg = over(parse(colour), bg);
      const large = size >= 24 || (size >= 18.66 && weight >= 700);
      const need = large ? 3 : 4.5, got = ratio(fg, bg);
      if (got < need - 0.005) bad.push(`${what}: ${got.toFixed(2)}:1 < ${need}`);
    };
    for (const e of document.querySelectorAll('body *')) {
      if (book && book.contains(e)) continue;
      if (!shown(e) || e.closest('[inert]')) continue;
      const style = getComputedStyle(e);
      if (e.matches('input, textarea') && e.getAttribute('placeholder') && !e.value) {
        const p = getComputedStyle(e, '::placeholder');
        check(e, p.color, `placeholder "${e.getAttribute('placeholder')}"`, parseFloat(p.fontSize), parseInt(p.fontWeight));
      }
      if (parseFloat(style.fontSize) === 0) continue;
      const own = [...e.childNodes].some(n => n.nodeType === 3 && n.textContent.trim());
      if (!own || e.disabled) continue;
      check(e, style.color, `"${named(e)}"`, parseFloat(style.fontSize), parseInt(style.fontWeight));
    }
    return bad;
  });
}

export async function stateCueShort(page) {
  return page.evaluate(() => {
    const shown = e => e.checkVisibility({ visibilityProperty: true, opacityProperty: true }) && e.getClientRects().length > 0;
    const parse = c => { const m = /rgba?\(([^)]+)\)/.exec(c); if (!m) return [0, 0, 0, 0]; const p = m[1].split(/[ ,\/]+/).filter(Boolean).map(Number); return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1]; };
    const over = (top, below) => { const a = top[3]; return [0, 1, 2].map(i => top[i] * a + below[i] * (1 - a)).concat([1]); };
    const ground = e => {
      const layers = [];
      for (let a = e; a; a = a.parentElement) { const c = parse(getComputedStyle(a).backgroundColor); if (c[3] > 0) { layers.push(c); if (c[3] >= 1) break; } }
      let base = [255, 255, 255, 1];
      for (let i = layers.length - 1; i >= 0; i--) base = over(layers[i], base);
      return base;
    };
    const lin = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
    const lum = c => 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]);
    const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
    const named = e => (e.getAttribute('aria-label') || e.textContent || e.id).trim().replace(/\s+/g, ' ').slice(0, 30);
    const bad = [];
    for (const e of document.querySelectorAll('[role=tab][aria-selected=true], [aria-pressed=true], [aria-current=true], [aria-current=page]')) {
      if (!shown(e) || e.closest('[inert]')) continue;
      const style = getComputedStyle(e), behind = ground(e.parentElement);
      // a switch draws its state on a part (its track), so the best of the element and its parts counts
      const fill = Math.max(...[e, ...e.querySelectorAll('*')].map(p => { const g = ground(p.parentElement); return ratio(over(parse(getComputedStyle(p).backgroundColor), g), g); }));
      const side = w => parseFloat(style[`border${w}Width`]) > 0 && style[`border${w}Style`] !== 'none'
        ? ratio(over(parse(style[`border${w}Color`]), behind), behind) : 0;
      const edge = Math.max(side('Top'), side('Bottom'), side('Left'), side('Right'));
      // a shadow or an outline drawn as a ring counts as an edge
      const shadow = style.boxShadow !== 'none' ? 3 : 0;
      const best = Math.max(fill, edge, shadow);
      if (best >= 3) continue;
      // otherwise the unchosen ones must differ by weight or underline
      const others = [...e.parentElement.children].filter(o => o !== e && o.matches('[role=tab], button'));
      const apart = others.some(o => { const s = getComputedStyle(o); return s.fontWeight !== style.fontWeight || s.textDecorationLine !== style.textDecorationLine; });
      if (!apart) bad.push(`"${named(e)}": chosen look ${best.toFixed(2)}:1 against ${others.length ? 'its row' : 'what it is on'}, nothing else sets it apart`);
    }
    return bad;
  });
}

export async function rowsCutByScroller(page) {
  return page.evaluate(() => {
    const book = document.querySelector('[role=document]');
    const shown = e => e.checkVisibility({ visibilityProperty: true, opacityProperty: true }) && e.getClientRects().length > 0;
    const named = e => (e.getAttribute('aria-label') || e.textContent || e.id || e.tagName).trim().replace(/\s+/g, ' ').slice(0, 36);
    const bad = [];
    const rows = 'button, a[href], select, input:not([type=hidden]), label, [role=button], [role=tab], [role=slider], [role=switch], h2, h3, p, li';
    for (const scroller of document.querySelectorAll('*')) {
      if (book && book.contains(scroller)) continue;
      const s = getComputedStyle(scroller);
      if (!/auto|scroll|hidden/.test(s.overflowY) || scroller.scrollHeight <= scroller.clientHeight + 1) continue;
      if (!shown(scroller) || scroller === document.documentElement || scroller === document.body) continue;
      const box = scroller.getBoundingClientRect();
      for (const e of scroller.querySelectorAll(rows)) {
        if (!shown(e)) continue;
        const r = e.getBoundingClientRect();
        if (r.height < 8) continue;
        const visible = Math.min(r.bottom, box.bottom) - Math.max(r.top, box.top);
        const share = visible / r.height;
        if (share > 0.05 && share < 0.95) bad.push(`${named(e)}: ${Math.round(share * 100)}% shown at the edge of ${scroller.id || scroller.className || scroller.tagName}`);
      }
    }
    return [...new Set(bad)];
  });
}

export async function rowsCovered(page) {
  return page.evaluate(() => {
    const book = document.querySelector('[role=document]');
    const shown = e => e.checkVisibility({ visibilityProperty: true, opacityProperty: true }) && e.getClientRects().length > 0;
    const named = e => (e.getAttribute('aria-label') || e.textContent || e.id || e.tagName).trim().replace(/\s+/g, ' ').slice(0, 36);
    const rows = 'button, a[href], select, input:not([type=hidden]), label, [role=button], [role=tab], [role=slider], [role=switch], h2, h3, p, li';
    const bad = [];
    for (const e of document.querySelectorAll(rows)) {
      if (book && book.contains(e)) continue;
      if (!shown(e) || e.closest('[inert]')) continue;
      const r = e.getBoundingClientRect();
      if (r.height < 8 || r.width < 8 || r.bottom < 0 || r.top > innerHeight) continue;
      let seen = 0, total = 0;
      for (let i = 0; i < 12; i++) {
        const y = r.top + (r.height * (i + 0.5)) / 12;
        if (y < 0 || y >= innerHeight) continue;
        total++;
        const hit = document.elementFromPoint(Math.min(Math.max(r.left + r.width / 2, 1), innerWidth - 1), y);
        if (hit && (hit === e || e.contains(hit) || hit.contains(e))) seen++;
      }
      if (total >= 6 && seen > 0 && seen < total) bad.push(`${named(e)}: ${Math.round(100 * seen / total)}% shown, the rest covered or cut`);
    }
    return [...new Set(bad)];
  });
}

export async function panelShare(page) {
  return page.evaluate(() => {
    const w = innerWidth, h = innerHeight;
    return [...document.querySelectorAll('[role=dialog], [role=toolbar]')]
      .filter(e => e.checkVisibility() && e.getClientRects().length > 0)
      .map(e => { const r = e.getBoundingClientRect(); return `${e.getAttribute('aria-label') || e.id}: ${Math.round(100 * Math.max(0, Math.min(r.bottom, h) - Math.max(r.top, 0)) / h)}% of the height, ${Math.round(100 * Math.max(0, Math.min(r.right, w) - Math.max(r.left, 0)) / w)}% of the width`; });
  });
}
