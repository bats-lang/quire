/**
 * The page's margins at its foot and head, measured (#296): a reflowed
 * page, paged or scrolled, with the bars down keeps its text clear of the running
 * footer, the footer clear of the screen's bottom inset (Android's
 * navigation bar), and its first line clear of the top inset (the
 * status bar). The fixture (fixtures.js) measures them at the end of
 * every test in the phone-sized projects, whenever the reader shows
 * such a page, so a spec that leaves the reader open checks them.
 *
 * What counts is the text as drawn: each line box cut to the page's
 * own scrollport (its client box, where the browser clips what it
 * scrolls), so a scrolled page whose text runs on under the footer or
 * a system bar fails, and one clipped at its reading area passes.
 *
 * The insets are the page's own, env(safe-area-inset-*) as computed
 * (a DevTools override, or none), never assumed, and full screen is
 * measured as any other state.
 *
 * The minimums (the choice and its sources are on quire#296's PR):
 * - text to the footer, and the first line to the top inset: half the
 *   page's line height, and never under 12 px;
 * - the footer's bottom to the bottom inset: 8 px (Material 3's
 *   spacing steps; what the system bars cover is padded by its inset).
 */

/** The least space, in CSS px, between the text and the footer or a
    screen's inset: half a line, at least this */
export const TEXT_CLEARANCE_LEAST = 12;

/** The least space between the footer's bottom and the bottom inset */
export const FOOTER_CLEARANCE = 8;

/** How the page shown measures: null when no reflowed page is
    shown with the bars down, else what was measured and each margin
    that falls short */
export async function pageMargins(page) {
  return page.evaluate(({ textLeast, footerClearance }) => {
    const reader = document.querySelector('.rv');
    if (!reader || !reader.checkVisibility()) return null;
    // the bars up cover the page's head and foot themselves
    if (!reader.classList.contains('chrome-off')) return null;
    const doc = reader.querySelector('[role=document]');
    if (!doc || !doc.checkVisibility()) return null;
    // a fixed page and a vertical one keep their own layouts
    if (['fixed', 'vertical', 'vertical-lr'].some(c => doc.classList.contains(c))) return null;
    const style = getComputedStyle(doc);
    const scrolled = style.overflowY === 'auto' || style.overflowY === 'scroll';
    const probe = document.createElement('div');
    probe.style.cssText = 'position:fixed;visibility:hidden;padding:env(safe-area-inset-top) 0 env(safe-area-inset-bottom)';
    document.body.append(probe);
    const probed = getComputedStyle(probe);
    const insetTop = parseFloat(probed.paddingTop);
    const insetBottom = parseFloat(probed.paddingBottom);
    probe.remove();
    const viewport = window.visualViewport;
    const shownTop = viewport ? viewport.offsetTop : 0;
    const shownBottom = viewport ? Math.min(innerHeight, viewport.offsetTop + viewport.height) : innerHeight;
    const line = parseFloat(style.lineHeight) || parseFloat(style.fontSize) * 1.2;
    const least = Math.max(textLeast, line / 2);
    const box = doc.getBoundingClientRect();
    // the scrollport: what the page draws of its text, scrolled or not
    const clipTop = box.top + doc.clientTop;
    const clipBottom = clipTop + doc.clientHeight;
    let first = Infinity;
    let last = -Infinity;
    let lines = 0;
    const footerElement = document.getElementById('footer');
    const footer = footerElement && footerElement.checkVisibility() ? footerElement.getBoundingClientRect() : null;
    // lines drawn at or under the footer: one cut by it, or the text
    // running on below it (#296, and full screen's #300)
    let underFooter = 0;
    const walker = document.createTreeWalker(doc, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (!node.data.trim()) continue;
      // raised and lowered text, and a ruby's reading, stand out of
      // their line by design
      if (node.parentElement.closest('sup,sub,rt,rtc,rp')) continue;
      const range = document.createRange();
      range.selectNodeContents(node);
      for (const r of range.getClientRects()) {
        // the page's other columns lie beside it, out of sight
        if (r.width <= 0 || r.right <= box.left + 1 || r.left >= box.right - 1) continue;
        // the part of the line drawn: scrolled, a line at the
        // scrollport's edge is cut there, and one past it is not drawn
        const top = Math.max(r.top, clipTop);
        const bottom = Math.min(r.bottom, clipBottom);
        if (bottom <= top) continue;
        first = Math.min(first, top);
        last = Math.max(last, bottom);
        lines++;
        if (footer && bottom > footer.top + 0.5) underFooter++;
      }
    }
    if (!lines) return null;
    const measured = {
      window: { width: innerWidth, height: innerHeight, shownTop, shownBottom },
      insets: { top: insetTop, bottom: insetBottom },
      line, least, scrolled,
      scrollport: { top: clipTop, bottom: clipBottom },
      firstLineTop: first, lastLineBottom: last,
      footer: footer ? { top: footer.top, bottom: footer.bottom } : null,
    };
    const short = [];
    const tolerance = 0.5;
    const headRoom = first - (shownTop + insetTop);
    if (headRoom < least - tolerance) short.push(`the first line is ${headRoom.toFixed(1)}px below the top inset, under ${least.toFixed(1)}px`);
    const insetLine = shownBottom - insetBottom;
    if (underFooter) short.push(`${underFooter} line boxes reach below the footer's top`);
    if (footer) {
      const footerRoom = insetLine - footer.bottom;
      if (footerRoom < footerClearance - tolerance) short.push(`the footer is ${footerRoom.toFixed(1)}px above the bottom inset, under ${footerClearance}px`);
      const textRoom = footer.top - last;
      if (textRoom < least - tolerance) short.push(`the last line is ${textRoom.toFixed(1)}px above the footer, under ${least.toFixed(1)}px`);
    } else {
      const textRoom = insetLine - last;
      if (textRoom < least - tolerance) short.push(`the last line is ${textRoom.toFixed(1)}px above the bottom inset, under ${least.toFixed(1)}px`);
    }
    return { measured, short };
  }, { textLeast: TEXT_CLEARANCE_LEAST, footerClearance: FOOTER_CLEARANCE });
}

/** The projects whose tests end with the margins measured: the phone
    sizes, where the page's head and foot are tightest */
export const MARGIN_PROJECTS = ['android', 'mobile-portrait', 'mobile-landscape', 'narrow'];

/** Fails when the page shown has a margin short (nothing to measure
    passes): what fell short, and what was measured */
export async function checkPageMargins(page, where = 'the page shown') {
  let found;
  try {
    found = await pageMargins(page);
  } catch (error) {
    // the page went away or is between documents: nothing is shown to measure
    if (/closed|destroyed|navigat/i.test(String(error))) return null;
    throw error;
  }
  if (found && found.short.length) {
    throw new Error(`${where}: ${found.short.join('; ')} (#296)\n${JSON.stringify(found.measured)}`);
  }
  return found;
}
