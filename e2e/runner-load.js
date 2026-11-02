/**
 * The runner's load, sampled while the suite runs (#600), so a test that
 * fails on a page that was slow to answer says whether the machine or the
 * page was slow. Every SAMPLE_EVERY_MS the worker reads, from /proc (Linux),
 * and keeps the last SAMPLE_KEEP samples (a minute and a half), across the tests of
 * one worker (#715): the sampler runs for the worker's life, so a test's capture
 * holds the load of the tests before it, which is the evidence for "the runner was
 * slow". Each sample says which test it was taken in (`test`, empty between tests):
 *   - /proc/pressure/{cpu,io,memory}: the "some" and "full" averages and the
 *     time stalled in the interval (the totals' difference);
 *   - /proc/loadavg and the running tasks;
 *   - /proc/stat's cpu line as the share of the interval spent in user,
 *     system, iowait, steal and idle (differences of the counters);
 *   - the CPU time of each process under this worker (the browsers) over the
 *     interval, and of the busiest other processes of the machine;
 *   - the worker's own lateness (a timer that fires late says the worker's
 *     event loop, or the machine, was not running it).
 * A source that cannot be read is written as "not available: why", once per
 * sample; nothing here throws, and the timer is unref'd, so a sample never
 * fails or holds up a test.
 *
 * No threshold is applied: the kernel's PSI documentation (docs.kernel.org,
 * accounting/psi) and LWN's account of it give no value of avg10 that
 * separates contention from none, and none was found for steal time, so
 * the summary states the numbers and ratios and the reader judges.
 */

import { readFileSync, readdirSync } from 'node:fs';
import { cpus } from 'node:os';

export const SAMPLE_EVERY_MS = 2000;
export const SAMPLE_KEEP = 45;
const OTHERS_MOST = 4;
export const STALL_LATE_MS = 300; // a sample this late is a stall of the machine or of the worker (the watchdog's GAP_MS)
const TICKS_PER_SECOND = 100; // USER_HZ, 100 on Linux for every architecture the runners use

const text = (file) => readFileSync(file, 'utf8');
const unavailable = (error) => `not available: ${error && error.code ? `${error.code} ${error.message}` : String(error && error.message || error)}`;
const attempt = (read) => { try { return read(); } catch (error) { return unavailable(error); } };

/** /proc/pressure/<resource>: { some: { avg10, avg60, avg300, totalUs }, full: ... } */
function pressure(resource) {
  return attempt(() => {
    const out = {};
    for (const line of text(`/proc/pressure/${resource}`).trim().split('\n')) {
      const [kind, ...fields] = line.trim().split(/\s+/);
      const values = Object.fromEntries(fields.map((field) => field.split('=')));
      out[kind] = { avg10: +values.avg10, avg60: +values.avg60, avg300: +values.avg300, totalUs: +values.total };
    }
    return out;
  });
}

/** /proc/stat's first line, in jiffies, and the tasks running. */
function stat() {
  return attempt(() => {
    const lines = text('/proc/stat').split('\n');
    const cpu = lines[0].trim().split(/\s+/).slice(1).map(Number);
    const [user, nice, system, idle, iowait = 0, irq = 0, softirq = 0, steal = 0] = cpu;
    const running = lines.find((line) => line.startsWith('procs_running'));
    return { user: user + nice, system: system + irq + softirq, idle, iowait, steal, procsRunning: running ? +running.split(/\s+/)[1] : null };
  });
}

/** Every process: pid -> { ppid, comm, ticks, rssPages }. */
function processes() {
  return attempt(() => {
    const all = new Map();
    for (const name of readdirSync('/proc')) {
      if (!/^\d+$/.test(name)) continue;
      try {
        const line = text(`/proc/${name}/stat`);
        const close = line.lastIndexOf(')');
        const fields = line.slice(close + 2).split(' ');
        // after "(comm) ": state is fields[0], ppid fields[1], utime fields[11], stime fields[12], rss fields[21]
        all.set(+name, { comm: line.slice(line.indexOf('(') + 1, close), ppid: +fields[1], ticks: +fields[11] + +fields[12], rssPages: +fields[21] });
      } catch (gone) { /* it ended while being read */ }
    }
    return all;
  });
}

/** The kind of a Chromium process, from its command line (`--type=renderer`), else its name. */
function kindOf(pid, comm) {
  try {
    const match = /--type=([a-z-]+)/.exec(text(`/proc/${pid}/cmdline`).replace(/\0/g, ' '));
    return match ? match[1] : comm;
  } catch (gone) { return comm; }
}

function descendants(all, root) {
  const children = new Map();
  for (const [pid, entry] of all) (children.get(entry.ppid) || children.set(entry.ppid, []).get(entry.ppid)).push(pid);
  const found = new Set();
  const stack = [...(children.get(root) || [])];
  while (stack.length) { const pid = stack.pop(); if (!found.has(pid)) { found.add(pid); stack.push(...(children.get(pid) || [])); } }
  return found;
}

let samples = [];
let previous = null;
let timer = null;
let testNow = '';

function sample(expectedAt) {
  const now = Date.now();
  const took = process.hrtime.bigint();
  const current = {
    at: now,
    pressure: { cpu: pressure('cpu'), io: pressure('io'), memory: pressure('memory') },
    loadAverage: attempt(() => text('/proc/loadavg').trim()),
    stat: stat(),
    all: processes(),
    workerCpuMs: Math.round((process.cpuUsage().user + process.cpuUsage().system) / 1000),
  };
  const out = { at: new Date(now).toISOString(), test: testNow, lateMs: expectedAt ? Math.max(0, now - expectedAt) : 0, pressure: {}, loadAverage: current.loadAverage };
  for (const resource of ['cpu', 'io', 'memory']) {
    const each = current.pressure[resource];
    const before = previous && previous.pressure[resource];
    out.pressure[resource] = typeof each === 'string' ? each : { ...each };
    if (typeof each !== 'string' && before && typeof before !== 'string') {
      for (const kind of Object.keys(each)) if (before[kind]) out.pressure[resource][kind] = { ...each[kind], stalledMs: Math.round((each[kind].totalUs - before[kind].totalUs) / 1000) };
    }
  }
  const intervalMs = previous ? now - previous.at : null;
  out.intervalMs = intervalMs;
  if (typeof current.stat === 'string') out.cpuShare = current.stat;
  else {
    out.procsRunning = current.stat.procsRunning;
    const before = previous && typeof previous.stat !== 'string' ? previous.stat : null;
    if (before) {
      const delta = Object.fromEntries(['user', 'system', 'idle', 'iowait', 'steal'].map((name) => [name, current.stat[name] - before[name]]));
      const total = Object.values(delta).reduce((sum, value) => sum + value, 0) || 1;
      out.cpuShare = Object.fromEntries(Object.entries(delta).map(([name, value]) => [name, +(100 * value / total).toFixed(1)]));
    }
  }
  if (typeof current.all === 'string') out.processes = current.all;
  else {
    const mine = descendants(current.all, process.pid);
    const used = (pid) => {
      const was = previous && typeof previous.all !== 'string' && previous.all.get(pid);
      return was && intervalMs ? +((current.all.get(pid).ticks - was.ticks) / TICKS_PER_SECOND).toFixed(3) : null;
    };
    const browser = [...mine].map((pid) => ({ pid, kind: kindOf(pid, current.all.get(pid).comm), cpuSeconds: used(pid), rssMiB: Math.round(current.all.get(pid).rssPages * 4 / 1024) }))
      .filter((entry) => entry.cpuSeconds === null || entry.cpuSeconds > 0.005).sort((a, b) => (b.cpuSeconds || 0) - (a.cpuSeconds || 0));
    const others = [...current.all].filter(([pid]) => !mine.has(pid) && pid !== process.pid).map(([pid, entry]) => ({ pid, comm: entry.comm, cpuSeconds: used(pid) }))
      .filter((entry) => entry.cpuSeconds).sort((a, b) => b.cpuSeconds - a.cpuSeconds).slice(0, OTHERS_MOST);
    out.browserProcesses = browser;
    out.browserCpuSeconds = +browser.reduce((sum, entry) => sum + (entry.cpuSeconds || 0), 0).toFixed(3);
    out.busiestOthers = others;
    const worker = previous ? (current.workerCpuMs - previous.workerCpuMs) / 1000 : null;
    out.workerCpuSeconds = worker === null ? null : +worker.toFixed(3);
  }
  out.sampleMs = Number(process.hrtime.bigint() - took) / 1e6;
  previous = current;
  samples.push(out);
  if (samples.length > SAMPLE_KEEP) samples.shift();
}

/** Starts (or joins) the worker's sampler, naming the test; the returned function ends the test's part. */
export function sampleRunner(test = '') {
  testNow = test;
  if (!timer) {
    let expected = Date.now() + SAMPLE_EVERY_MS;
    try { sample(0); } catch (error) { /* a sample is never worth a test */ }
    timer = setInterval(() => {
      try { sample(expected); } catch (error) { samples.push({ at: new Date().toISOString(), error: unavailable(error) }); if (samples.length > SAMPLE_KEEP) samples.shift(); }
      expected = Date.now() + SAMPLE_EVERY_MS;
    }, SAMPLE_EVERY_MS);
    timer.unref();
  }
  let left = false;
  return () => {
    if (left) return;
    left = true;
    // the sampler and its samples stay: the next test of this worker reads them
    // (the timer is unref'd, so it holds nothing up). A newer test's name stays.
    if (testNow === test) testNow = '';
  };
}

/** Memory reclaim (quire#909): the memory pressure (`some`, microseconds) of a stall covers most (more than half) of its gap. */
export function memoryReclaim(gapMs, memoryUs) {
  return typeof memoryUs === 'number' && typeof gapMs === 'number' && gapMs > 0 && memoryUs / 1000 > gapMs / 2;
}

/** The samples whose timer came late, each with the memory pressure that stalled tasks in its interval and whether that is memory reclaim. */
export function lateSamples(taken) {
  return taken.filter((each) => each.lateMs >= STALL_LATE_MS).map((each) => {
    const memory = each.pressure && each.pressure.memory && each.pressure.memory.some;
    const memoryStalledMs = memory && typeof memory.stalledMs === 'number' ? memory.stalledMs : null;
    return { at: each.at, lateMs: each.lateMs, memoryStalledMs, memoryReclaim: memoryReclaim(each.lateMs, memoryStalledMs === null ? null : memoryStalledMs * 1000) };
  });
}

const peak = (values) => (values.length ? Math.max(...values) : null);
const mean = (values) => (values.length ? +(values.reduce((sum, value) => sum + value, 0) / values.length).toFixed(2) : null);

/** The samples taken in the last `ms`, with what they add up to (numbers and ratios, no verdict). */
export function runnerLoad(ms = 60000, source = samples) {
  const since = Date.now() - ms;
  const taken = source.filter((each) => !each.at || Date.parse(each.at) >= since);
  const some = (resource) => taken.map((each) => each.pressure && each.pressure[resource] && each.pressure[resource].some && each.pressure[resource].some.avg10).filter((value) => typeof value === 'number');
  const share = (name) => taken.map((each) => each.cpuShare && each.cpuShare[name]).filter((value) => typeof value === 'number');
  const browserCpu = taken.map((each) => each.browserCpuSeconds).filter((value) => typeof value === 'number');
  const intervals = taken.map((each) => each.intervalMs).filter((value) => typeof value === 'number');
  const cores = cpus().length;
  const summary = {
    windowMs: ms,
    samples: taken.length,
    cores,
    cpuPressureSomeAvg10: { peak: peak(some('cpu')), mean: mean(some('cpu')) },
    ioPressureSomeAvg10: { peak: peak(some('io')), mean: mean(some('io')) },
    memoryPressureSomeAvg10: { peak: peak(some('memory')), mean: mean(some('memory')) },
    stealPercent: { peak: peak(share('steal')), mean: mean(share('steal')) },
    iowaitPercent: { peak: peak(share('iowait')), mean: mean(share('iowait')) },
    idlePercent: { min: share('idle').length ? Math.min(...share('idle')) : null, mean: mean(share('idle')) },
    workerLateMs: { peak: peak(taken.map((each) => each.lateMs).filter((value) => typeof value === 'number')) },
    // cores' worth of CPU the browsers used per second, over the samples that have it
    browserCores: intervals.length && browserCpu.length ? { peak: +Math.max(...taken.filter((each) => each.intervalMs && typeof each.browserCpuSeconds === 'number').map((each) => each.browserCpuSeconds / (each.intervalMs / 1000))).toFixed(2), mean: +(browserCpu.reduce((a, b) => a + b, 0) / (intervals.reduce((a, b) => a + b, 0) / 1000)).toFixed(2) } : 'not available: fewer than two samples, or /proc/<pid>/stat unreadable',
  };
  const notAvailable = [...new Set(taken.flatMap((each) => [each.cpuShare, each.processes, ...Object.values(each.pressure || {})].filter((value) => typeof value === 'string')))];
  summary.notAvailable = notAvailable;
  summary.stalls = lateSamples(taken);
  const reclaims = summary.stalls.filter((each) => each.memoryReclaim);
  summary.reading = `over the last ${Math.round(ms / 1000)} s (${taken.length} samples) on ${cores} cores: CPU pressure (some, avg10) peak ${summary.cpuPressureSomeAvg10.peak}%, steal peak ${summary.stealPercent.peak}%, iowait peak ${summary.iowaitPercent.peak}%, the browsers used ${typeof summary.browserCores === 'string' ? summary.browserCores : `${summary.browserCores.mean} cores on average, ${summary.browserCores.peak} at most`}, the worker's timer was late by ${summary.workerLateMs.peak} ms at most${reclaims.length ? `; memory reclaim: ${reclaims.map((each) => `memory pressure stalled tasks for ${each.memoryStalledMs} ms of the sample at ${each.at} whose timer was ${each.lateMs} ms late`).join(', ')}` : ''}`;
  return { everyMs: SAMPLE_EVERY_MS, summary, samples: taken };
}
