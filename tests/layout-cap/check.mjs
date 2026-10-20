// The layout cap of the e2e helpers (#600, LAYOUT_CAP_MS in e2e/helpers.js).
// Run with node: no browser, a fake page whose frame reads are given, and a
// fake test info. Checks that a reading of 3 s gives the uncapped timeouts and
// a reading of 60 s gives the timeouts of the cap, on every path a layout sets.
//
//   node tests/layout-cap/check.mjs

import assert from 'node:assert/strict';
import {
  LAYOUT_CAP_MS, layoutCapped, stepExpectMs, clickAllowanceMs, triesAllowanceMs,
} from '../../e2e/helpers.js';
import { layoutBudget } from '../../e2e/layout-budget.js';

// bareFrameMs asks the page once per read, and the readings come in order
const pageReading = (...readings) => ({ evaluate: async () => readings.shift() });

// layoutBudget sets the test's timeout and attaches its figures
function testInfoAt(timeout) {
  const info = {
    timeout,
    attached: null,
    setTimeout(ms) { info.timeout = ms; },
    async attach(name, { body }) { info.attached = JSON.parse(body); },
  };
  return info;
}

assert.equal(LAYOUT_CAP_MS, 30000, 'the cap is 30 s (see the comment on it)');
assert.equal(layoutCapped(3000), 3000, 'a layout under the cap is not changed');
assert.equal(layoutCapped(60000), LAYOUT_CAP_MS, 'a layout over the cap is taken as the cap');

// the timeouts a layout sets, at 3 s (uncapped) and at 60 s (capped to 30 s)
assert.equal(stepExpectMs(3000), 20000, 'an assertion: 5 x 3 s + 5 s');
assert.equal(clickAllowanceMs(3000), 10000, 'a click: 3 x 3 s + 1 s');
assert.equal(triesAllowanceMs(3000), 29000, 'the tries: 20 s + 3 x 3 s');
assert.equal(stepExpectMs(60000), 155000, 'an assertion at the cap: 5 x 30 s + 5 s');
assert.equal(clickAllowanceMs(60000), 91000, 'a click at the cap: 3 x 30 s + 1 s');
assert.equal(triesAllowanceMs(60000), 110000, 'the tries at the cap: 20 s + 3 x 30 s');
assert.equal(stepExpectMs(60000), stepExpectMs(LAYOUT_CAP_MS));
assert.equal(clickAllowanceMs(60000), clickAllowanceMs(LAYOUT_CAP_MS));
assert.equal(triesAllowanceMs(60000), triesAllowanceMs(LAYOUT_CAP_MS));
// no layout: the config's 15 s, and the click and tries as before (2 s, 20 s)
assert.equal(stepExpectMs(0), 15000);
assert.equal(clickAllowanceMs(0), 2000);
assert.equal(triesAllowanceMs(0), 20000);

// layoutBudget: a reading of 3 s gives the uncapped test budget
{
  const info = testInfoAt(90000);
  const { layoutMs, expectMs } = await layoutBudget(pageReading(3000, 3000), info, Date.now());
  assert.equal(layoutMs, 3000);
  assert.equal(expectMs, 20000);
  assert.equal(info.attached.layoutCappedMs, 3000);
  assert.equal(info.timeout, info.attached.elapsedMs + 20 * 3000 + 40000, 'the test: elapsed + 20 x 3 s + 40 s');
}

// layoutBudget: a reading of 60 s gives the capped budgets
{
  const info = testInfoAt(90000);
  const { layoutMs, expectMs } = await layoutBudget(pageReading(60000, 60000), info, Date.now());
  assert.equal(layoutMs, 60000, 'the reading itself is kept, for the record');
  assert.equal(info.attached.layoutCappedMs, LAYOUT_CAP_MS);
  assert.equal(expectMs, 155000);
  assert.equal(info.timeout, info.attached.elapsedMs + 20 * LAYOUT_CAP_MS + 40000, 'the test: elapsed + 20 x 30 s + 40 s');
}

// layoutBudget: the first read (warming up) is the larger, and is the one taken
{
  const info = testInfoAt(90000);
  const { layoutMs } = await layoutBudget(pageReading(3500, 1750), info, Date.now());
  assert.equal(layoutMs, 3500);
}

console.log(`layout-cap: ok (cap ${LAYOUT_CAP_MS} ms)`);
