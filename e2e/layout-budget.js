// The time a test that works on a long chapter in columns may take is the
// layout's, not a fixed number (#600). Chrome lays the columns of a text of
// 64 KiB or more out as one task after each change of the page (#423, #522),
// and a step that follows it (a search, a selection, a click) is answered when
// that task has ended. On a runner that is twice as slow the task is twice as
// long, the step is, and so the test: a fixed 15 s for an assertion and 90 s
// for the test fail a test that is correct (the failing run of #600 took 71 s
// where the same test took 24 s on a normal runner).
//
// The measure is `bareFrameMs`, Chrome's own time to lay out and draw a copy
// of the page's DOM here and now, so a slow runner is slow in it as in the
// page. The multiples below come from measuring the giant text in columns on
// the phone project (this spec, unloaded, bareFrameMs 1.75 s warm and 3.5 s
// on the first read): one search and selection took 4.2 to 6.3 s (2.4 to 3.6
// times the warm frame), the four highlights 25 s (14 times), and the rest of
// the test 19 s. Each budget is that, with headroom of a third or more, and
// none is smaller than what the config gives.

import { bareFrameMs, layoutCapped, stepExpectMs } from './helpers.js';

/** The four highlights of the test, in layouts: measured 14, given 20 */
const WORK_TIMES = 20;
/** What the test does besides: measured 19 s, given twice that */
const REST_MS = 40000;

/** Measures the layout the page is in and makes the test's budgets from it:
    the test's timeout (set once, never lowered) and the timeout of an
    assertion that follows a layout. Notes what was measured in the test's
    attachments, so a failure shows the layout it was given.
    `startedAt` is `Date.now()` taken as the test began: Playwright's timeout
    counts from there, so what has run already is part of it. */
export async function layoutBudget(page, testInfo, startedAt, { floorExpectMs = 15000 } = {}) {
  const first = await bareFrameMs(page); // the first read includes warming up: the larger
  const warm = await bareFrameMs(page);
  const layoutMs = Math.max(first, warm);
  // the budgets take the layout as LAYOUT_CAP_MS bounds it (helpers.js), so a
  // reading of a minute gives the timeouts of 30 s, not of a minute
  const cappedMs = layoutCapped(layoutMs);
  const elapsedMs = Date.now() - startedAt;
  const expectMs = stepExpectMs(layoutMs, floorExpectMs);
  const testMs = Math.max(testInfo.timeout, elapsedMs + WORK_TIMES * cappedMs + REST_MS);
  testInfo.setTimeout(testMs);
  await testInfo.attach('layout-budget.json', {
    body: JSON.stringify({ firstFrameMs: first, warmFrameMs: warm, layoutMs, layoutCappedMs: cappedMs, expectMs, testMs, elapsedMs }, null, 2),
    contentType: 'application/json',
  });
  return { layoutMs, expectMs, testMs };
}
