/**
 * The attempts of the helpers that try an action again (#600): how long
 * each took, why it was tried again, and what the page's main thread did in
 * that time (DevTools' Performance.getMetrics before and after). The stall
 * watch (stall-capture.js) binds a log to each page it arms; a helper with
 * no log bound (a page the watch does not know) runs as it always did.
 *
 * Nothing here can fail or hang a test: a log is a note, every read of the
 * page is bounded, and a read that fails is written as "not available: why".
 */

const logs = new WeakMap(); // page -> log
const ENTRIES_MOST = 300;
const WHY_MOST = 300;

/** Bound by the stall watch: `log.metrics()` and `log.harvest()` never reject. */
export function bindAttempts(page, log) {
  logs.set(page, log);
}

export function attemptsOf(page) {
  return logs.get(page) || null;
}

const reason = (failure) => String(failure && failure.message || failure).split('\n')[0].slice(0, WHY_MOST);

/**
 * Runs `work`, noting how long it took and whether it failed (and why), with
 * what the page's main thread did meanwhile. `detail` is written as given.
 * The work's own result, or its own failure, is returned, unchanged. The
 * entry is `entry`-shaped: { step, attempt, startedAt, ms, outcome, why,
 * devtools, ...detail }; `note.set(more)` (the third argument of `work`)
 * adds what the work learns on the way (why it will try again).
 */
export async function attempted(page, step, attempt, work, detail = {}) {
  const log = logs.get(page);
  if (!log) return work({ set() {} });
  const entry = { step, attempt, startedAt: new Date().toISOString(), ...detail };
  const began = Date.now();
  const before = await log.metrics().catch((error) => ({ unavailable: reason(error) }));
  try {
    const value = await work({ set: (more) => Object.assign(entry, more) });
    entry.outcome = 'ok';
    return value;
  } catch (failure) {
    entry.outcome = 'failed';
    entry.why = reason(failure);
    throw failure;
  } finally {
    entry.ms = Date.now() - began;
    const after = await log.metrics().catch((error) => ({ unavailable: reason(error) }));
    entry.devtools = metricsBetween(before, after, entry.ms);
    log.push(entry);
    // a failed attempt's long tasks are taken now, while the page is there
    if (entry.outcome === 'failed') await log.harvest().catch(() => {});
  }
}

/** A note with no work to time: a decision, such as why an action is tried again. */
export function noted(page, step, attempt, detail) {
  const log = logs.get(page);
  if (log) log.push({ step, attempt, startedAt: new Date().toISOString(), outcome: 'note', ...detail });
}

const COUNTS = ['LayoutCount', 'RecalcStyleCount', 'Nodes'];

/**
 * What the page's main thread did between two Performance.getMetrics reads,
 * in milliseconds: the time in tasks, script, layout, style, and the CPU the
 * thread and the process got (`threadCpuMs`, `processCpuMs`). A main thread
 * that was busy for most of the wall time but got little CPU was not given
 * the machine (a slow runner); one that got the CPU it used was slow itself.
 * `reading` says that in words when the numbers allow.
 */
export function metricsBetween(before, after, wallMs) {
  if (!before || !after || before.unavailable || after.unavailable) {
    return { unavailable: `not available: ${(before && before.unavailable) || (after && after.unavailable) || 'no metrics'}` };
  }
  const out = { wallMs };
  const ms = (name) => (after[name] !== undefined && before[name] !== undefined ? Math.round((after[name] - before[name]) * 1000) : null);
  out.taskMs = ms('TaskDuration');
  out.scriptMs = ms('ScriptDuration');
  out.layoutMs = ms('LayoutDuration');
  out.recalcStyleMs = ms('RecalcStyleDuration');
  out.v8CompileMs = ms('V8CompileDuration');
  out.threadCpuMs = ms('ThreadTime');
  out.processCpuMs = ms('ProcessTime');
  for (const name of COUNTS) out[name[0].toLowerCase() + name.slice(1)] = after[name] !== undefined && before[name] !== undefined ? after[name] - before[name] : null;
  out.metricsWallMs = ms('Timestamp');
  if (out.taskMs !== null && out.threadCpuMs !== null && out.taskMs >= 200) {
    const share = Math.round((100 * out.threadCpuMs) / Math.max(out.taskMs, 1));
    out.reading = `the main thread ran tasks for ${out.taskMs} ms of ${wallMs} ms and got ${out.threadCpuMs} ms of CPU (${share}% of its task time)`;
  }
  return out;
}
