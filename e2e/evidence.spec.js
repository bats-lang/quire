/**
 * Completeness of the evidence (#575), proved by induced faults: for each class of failure the table on quire#575
 * lists, a test makes it happen on purpose and asserts that the artifact holds the field that identifies it. Where the
 * class is not this suite's to cause (a hypervisor stall, memory corruption), the test induces what the substitute
 * observes. The recorder must be on (CI, or QUIRE_FLIGHT=1 with sudo): these tests prove what it lands. Keyword: evidence.
 */

import { createServer } from 'node:http';
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { gunzipSync } from 'node:zlib';
import { test, expect } from './fixtures.js';
import { arm, capture, CAPTURE_MOST_MS, NATIVE_MOST_MS, stallWatch as makeWatch } from './stall-capture.js';
import { diskEvidence, missingEvidence, symbolEvidence } from './evidence.js';
import { missingFields } from './evidence-check.js';
import { INSTANCE_VARIABLE, keepBoth, keepKernel, resumeKernel, ringState, startKernel, startWatchdog, stopKernel, stopWatchdog, wanted } from './flight-recorder.js';
import { Watchdog } from './flight-watchdog.js';

function desktopOnly(testInfo) {
  test.skip(testInfo.project.name !== 'desktop', 'the renderer and the machine do not depend on the project: once, in desktop, is enough');
}

/** The recorder is on: these tests prove what it records, so a run without it fails here, saying how to turn it on. */
async function recorderOn() {
  expect(wanted(), 'run with CI=true or QUIRE_FLIGHT=1 (and sudo): the evidence tests prove what the recorder lands').toBe(true);
  expect(process.env[INSTANCE_VARIABLE], 'the kernel ring started in global setup').toBeTruthy();
  await resumeKernel();
}

const ring = (file) => gunzipSync(readFileSync(file)).toString();
const processes = async (browser) => {
  const session = await browser.newBrowserCDPSession();
  try { return (await session.send('SystemInfo.getProcessInfo')).processInfo; } finally { await session.detach(); }
};

/** A synchronous request to a server that never answers: the main thread is blocked in an untimed futex wait, as in #575. */
async function hangPage(page, stallWatch) {
  const held = new Set();
  const server = createServer(() => { /* never answers */ });
  server.on('connection', (socket) => held.add(socket));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  await page.setContent('<!doctype html><title>Hung</title><p>Hung</p>');
  const session = await stallWatch.session(page);
  await session.send('Runtime.evaluate', { expression: `setTimeout(() => { const request = new XMLHttpRequest(); request.open('GET', 'http://127.0.0.1:${port}/never', false); request.send(); }, 0)` });
  return { release() { for (const socket of held) socket.destroy(); server.close(); } };
}

test('an untimed futex wait in the renderer\'s main thread: the word, its neighbours, the waker candidates, the kernel ring, the trace and the symbols land', async ({ page, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  test.setTimeout(testInfo.timeout + NATIVE_MOST_MS);
  const hang = await hangPage(page, stallWatch);
  let found;
  try { found = await stallWatch.next(page, 20000 + NATIVE_MOST_MS); } finally { hang.release(); }
  expect(found.flight.error).toBeUndefined();
  const word = (found.futex || []).find((each) => each.untimed);
  expect(word, `a renderer waits in an untimed futex: ${JSON.stringify(found.futex)}`).toBeTruthy();
  // the word and what is around it, as the process holds them
  expect(word.memory.bytes, JSON.stringify(word.memory)).toMatch(/^[0-9a-f]{128}$/);
  // the threads that could signal it
  expect(word.candidates.length).toBeGreaterThan(1);
  expect(word.candidates.some((thread) => /IO|Compositor|ThreadPool/.test(thread.comm))).toBe(true);
  // the kernel ring: this thread's wait on this address, untimed, and what woke it last
  const history = word.ring;
  expect(history.error, JSON.stringify(history)).toBeUndefined();
  expect(history.waiter.lastWait.untimed).toBe(true);
  expect(history.waiter.lastWait.address.replace(/^0+/, '')).toBe(word.address.replace(/^0+/, ''));
  expect(history.waiter.sleepingMs).toBeGreaterThanOrEqual(0);
  expect(Array.isArray(history.onAddress.wakers)).toBe(true);
  // the ring is the run's, with the CPU-level story around the wait
  const text = ring(found.flight.kernel.file);
  expect(text).toContain('sched_switch');
  // Chrome's trace holds the renderer's own events
  const trace = JSON.parse(gunzipSync(readFileSync(found.flight.browserTrace.file)).toString());
  expect((trace.traceEvents || trace).some((event) => event.pid === word.pid)).toBe(true);
  // the frames: named, or unavailable with the reason and the module and offset of each frame to resolve them later
  const symbols = found.symbols.find((each) => each.pid === word.pid);
  expect(symbols.buildId).toMatch(/^[0-9a-f]{40}$/);
  if (symbols.named === 0) {
    expect(symbols.state).toMatch(/^unavailable: .*build id [0-9a-f]{40}/);
    expect(symbols.unnamed.length).toBeGreaterThan(0);
    expect(symbols.unnamed[0].module).toBeTruthy();
  }
  expect(found.test).toBe(testInfo.title);
  expect(found.pageAgeMs).toBeGreaterThan(0);
  expect(found.disk.length).toBeGreaterThanOrEqual(3);
});

test('a script spin: the capture names the function, and no native attach is made to a busy renderer', async ({ page, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  test.setTimeout(testInfo.timeout + CAPTURE_MOST_MS);
  await page.setContent('<!doctype html><p>spin</p>');
  const session = await stallWatch.session(page);
  await session.send('Runtime.evaluate', { expression: 'setTimeout(function spinForeverForEvidence() { for (;;) {} }, 0)' });
  const found = await stallWatch.next(page, 30000 + CAPTURE_MOST_MS);
  expect(found.paused.frames[0].functionName).toBe('spinForeverForEvidence');
  expect(found.presumedBusy).toBeTruthy();
  expect(found.native).toBeUndefined();
  await session.send('Runtime.terminateExecution');
  await expect.poll(() => page.evaluate(() => 1)).toBe(1);
});

test('a renderer that crashes: the browser reports it, and the ring holds the signal and the exit', async ({ browser, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  const context = await browser.newContext();
  const crashing = await context.newPage();
  await crashing.setContent('<p>about to crash</p>');
  const before = (await processes(browser)).filter((each) => each.type === 'renderer').map((each) => each.id);
  crashing.goto('chrome://crash').catch(() => {});
  await expect.poll(() => stallWatch.state.flight, { timeout: 60000 }).toBeTruthy();
  const gone = before.filter((pid) => !existsSync(`/proc/${pid}`));
  expect(gone.length, 'one renderer died').toBeGreaterThanOrEqual(1);
  const text = ring(stallWatch.state.flight.kernel.file);
  expect(gone.some((pid) => new RegExp(`signal_generate: sig=11 .*pid=${pid} `).test(text) || new RegExp(`sched_process_exit: .*pid=${pid} `).test(text)), 'the signal or the exit of the renderer is in the ring').toBe(true);
  const written = readdirSync(testInfo.outputDir).filter((name) => /^crash-\d+\.json$/.test(name));
  expect(written.length).toBeGreaterThan(0);
  const body = JSON.parse(readFileSync(join(testInfo.outputDir, written[0]), 'utf8'));
  expect(body.reason).toMatch(/crashed/);
  expect(body.kernelLog).toBeTruthy();
  expect(body.flight.browserTrace.file, 'the browser lived, so its trace is there').toBeTruthy();
  await context.close();
  await resumeKernel();
});

test('a memory error a sanitizer finds in a process of the run: its report is in the crash capture', async ({ browser, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  const directory = testInfo.outputPath('asan');
  mkdirSync(directory, { recursive: true });
  const source = testInfo.outputPath('use-after-free.c');
  const program = testInfo.outputPath('use-after-free');
  writeFileSync(source, '#include <stdlib.h>\nint main(void) { char *p = malloc(8); free(p); p[0] = 1; return 0; }\n');
  const built = spawnSync('gcc', ['-fsanitize=address', '-g', source, '-o', program], { encoding: 'utf8' });
  expect(built.status, built.stderr).toBe(0);
  const ran = spawnSync(program, [], { encoding: 'utf8', env: { ...process.env, ASAN_OPTIONS: `log_path=${directory}/asan:detect_leaks=0` } });
  expect(ran.status).not.toBe(0);
  const kept = process.env.QUIRE_SANITIZER_LOGS;
  process.env.QUIRE_SANITIZER_LOGS = directory;
  try {
    const context = await browser.newContext();
    const crashing = await context.newPage();
    await crashing.setContent('<p>about to crash</p>');
    crashing.goto('chrome://crash').catch(() => {});
    await expect.poll(() => stallWatch.state.flight, { timeout: 60000 }).toBeTruthy();
    await expect.poll(() => readdirSync(testInfo.outputDir).some((name) => /^crash-\d+\.json$/.test(name)), { timeout: 30000 }).toBe(true);
    const body = JSON.parse(readFileSync(join(testInfo.outputDir, readdirSync(testInfo.outputDir).find((name) => /^crash-\d+\.json$/.test(name))), 'utf8'));
    expect(body.sanitizer[0].summary).toMatch(/AddressSanitizer: heap-use-after-free/);
    expect(body.sanitizer[0].head).toContain('use-after-free.c');
    await context.close();
  } finally {
    if (kept === undefined) delete process.env.QUIRE_SANITIZER_LOGS; else process.env.QUIRE_SANITIZER_LOGS = kept;
    await resumeKernel();
  }
});

test('a browser process killed: the ring holds the signal and the exit, and the trace says why it is not there', async ({ playwright, launchOptions }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  const own = await playwright.chromium.launch(launchOptions);
  const watch = makeWatch(own, testInfo);
  try {
    const context = await own.newContext();
    await context.newPage();
    const browserPid = (await processes(own)).find((each) => each.type === 'browser').id;
    process.kill(browserPid, 'SIGSEGV');
    await expect.poll(() => watch.state.flight, { timeout: 60000 }).toBeTruthy();
    const text = ring(watch.state.flight.kernel.file);
    expect(text).toMatch(new RegExp(`signal_generate: sig=11 .*pid=${browserPid} `));
    expect(text).toMatch(new RegExp(`sched_process_exit: .*pid=${browserPid} `));
    expect(watch.state.browserGone).toBe(true);
    expect(watch.state.flight.browserTrace.unavailable || watch.state.flight.browserTrace.error, 'the missing trace says why').toBeTruthy();
    expect(await watch.verify(), 'a dead browser needs no trace').toEqual([]);
  } finally {
    await watch.stop();
    await own.close().catch(() => {});
    await resumeKernel();
  }
});

test('a frozen compositor (the GPU process stopped): the page answers but makes no frame, and the capture shows the stopped process', async ({ page, browser }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  test.setTimeout(testInfo.timeout + CAPTURE_MOST_MS);
  await page.setContent('<p>no frames</p>');
  const gpu = (await processes(browser)).find((each) => each.type === 'GPU').id;
  const armed = await arm(page);
  process.kill(gpu, 'SIGSTOP');
  let found;
  try { found = await capture(page, armed, 'induced: the GPU process is stopped', browser); } finally { process.kill(gpu, 'SIGCONT'); }
  expect(found.answers.task.answered, 'the main thread answers').toBe(true);
  expect(found.frames.answered, 'but no frame is produced').toBe(false);
  const stopped = found.otherProcesses.find((each) => each.pid === gpu);
  expect(stopped.threads.join(' '), 'the GPU process is stopped').toMatch(/ T /);
});

test('a service worker that never answers a fetch: its state is in the capture and the request, which reaches no network layer, in the browser trace', async ({ page, browser }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  test.setTimeout(testInfo.timeout + CAPTURE_MOST_MS);
  const server = createServer((request, response) => {
    if (request.url === '/sw.js') {
      response.writeHead(200, { 'content-type': 'text/javascript' });
      response.end("self.addEventListener('install', () => self.skipWaiting()); self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim())); self.addEventListener('fetch', (event) => { if (event.request.url.endsWith('/hang')) event.respondWith(new Promise(() => {})); });");
    } else {
      response.writeHead(200, { 'content-type': 'text/html' });
      response.end('<!doctype html><title>sw</title><p>sw</p>');
    }
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    await page.goto(`${base}/`);
    await page.evaluate(() => navigator.serviceWorker.register('/sw.js'));
    await page.evaluate(() => navigator.serviceWorker.ready);
    await page.reload();
    await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller)).toBe(true);
    const armed = await arm(page);
    await page.evaluate(() => { fetch('/hang').catch(() => {}); });
    await new Promise((resolve) => setTimeout(resolve, 1500));
    const found = await capture(page, armed, 'induced: a fetch the service worker never answers', browser);
    expect(found.serviceWorker.controller.state).toBe('activated');
    expect(found.serviceWorker.registrations[0].active).toBe('activated');
    // the request reaches no network layer, so the page's request events do not show it: Chrome's trace does
    const kept = await keepBoth(browser, (name) => testInfo.outputPath(`sw-${name}`), process.env, true);
    expect(kept.browserTrace.file, JSON.stringify(kept.browserTrace)).toBeTruthy();
    expect(kept.browserTrace.pendingRequests.some((each) => each.url.endsWith('/hang') && each.ageMs >= 1000), JSON.stringify(kept.browserTrace.pendingRequests)).toBe(true);
    expect(kept.browserTrace.pendingRequests.some((each) => each.url.endsWith('/sw.js'))).toBe(false);
  } finally {
    server.closeAllConnections();
    server.close();
  }
});

test('a full disk and a disk that is slow: the free space is in the capture, and the ring holds the block requests', async ({ page, browser }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  // a 1 MiB tmpfs filled to its last block (mount needs root: the runners' sudo)
  const mountpoint = testInfo.outputPath('small-disk');
  mkdirSync(mountpoint, { recursive: true });
  const root = typeof process.getuid === 'function' && process.getuid() === 0;
  const mounted = spawnSync(...(root ? ['mount', ['-t', 'tmpfs', '-o', 'size=1m', 'tmpfs', mountpoint]] : ['sudo', ['-n', 'mount', '-t', 'tmpfs', '-o', 'size=1m', 'tmpfs', mountpoint]]), { encoding: 'utf8' });
  expect(mounted.status, `mount: ${mounted.stderr}`).toBe(0);
  const kept = process.env.QUIRE_EVIDENCE_PATHS;
  process.env.QUIRE_EVIDENCE_PATHS = mountpoint;
  try {
    spawnSync('dd', ['if=/dev/zero', `of=${join(mountpoint, 'fill')}`, 'bs=64k'], { encoding: 'utf8' }); // ends with "No space left on device"
    const full = diskEvidence().find((each) => each.path === mountpoint);
    expect(full.freeBytes, JSON.stringify(full)).toBeLessThan(65536);
    await page.setContent('<p>disk</p>');
    const found = await capture(page, await arm(page), 'induced: the disk is full', browser);
    expect(found.disk.find((each) => each.path === mountpoint).freeBytes).toBeLessThan(65536);
    // a slow disk is the gap between a block request and its completion: the requests are in the ring
    const written = join(testInfo.outputPath('direct-write'));
    const wrote = spawnSync('dd', ['if=/dev/zero', `of=${written}`, 'bs=1M', 'count=8', 'oflag=direct'], { encoding: 'utf8' });
    expect(wrote.status, wrote.stderr).toBe(0);
    const kernel = await keepKernel(testInfo.outputPath('disk-ring.txt.gz'), process.env, true);
    expect(kernel.error, JSON.stringify(kernel)).toBeUndefined();
    expect(ring(kernel.file)).toContain('block_rq_issue');
  } finally {
    if (kept === undefined) delete process.env.QUIRE_EVIDENCE_PATHS; else process.env.QUIRE_EVIDENCE_PATHS = kept;
    spawnSync(...(root ? ['umount', [mountpoint]] : ['sudo', ['-n', 'umount', mountpoint]]), { encoding: 'utf8' });
  }
});

test('a missing symbol file: the frames stay unnamed, and the capture says why and keeps what resolves them later', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const id = 'c97a9c1daed9622d2d0f626ce0e85170e6e105f2';
  const renderer = { pid: 1, buildId: id, binary: { hasSymtab: false, hasDebugLink: true }, gdbStacks: { mainThread: { frames: [{ text: '#0  0x00007f01 in __GI___futex_abstimed_wait_cancelable64 () from /lib/libc.so.6', pc: '0x00007f01' }, { text: '#1  0x00005601 in ?? ()', pc: '0x00005601', module: '/chrome/headless', offset: '0x1a5d073' }] } } };
  const lacking = symbolEvidence({ renderers: [renderer] }, { QUIRE_SYMBOLS_DIR: testInfo.outputPath('empty') })[0];
  expect(lacking.state).toMatch(/^unavailable: .*build id c97a9c1d/);
  expect(lacking.named).toBe(1);
  expect(lacking.unnamed).toEqual([{ pc: '0x00005601', module: '/chrome/headless', offset: '0x1a5d073' }]);
  // and when the debug file for the build id is there, the state says so
  const directory = testInfo.outputPath('symbols', '.build-id', id.slice(0, 2));
  mkdirSync(directory, { recursive: true });
  writeFileSync(join(directory, `${id.slice(2)}.debug`), 'x');
  expect(symbolEvidence({ renderers: [renderer] }, { QUIRE_SYMBOLS_DIR: testInfo.outputPath('symbols') })[0].state).toMatch(/^debug file found: /);
});

test('a recorder that does not start is said, and a red without its record is the named failure EVIDENCE MISSING', async ({ playwright, launchOptions }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  // the ring cannot start where there is no tracefs
  const nowhere = await startKernel({ CI: 'true', QUIRE_FLIGHT_TRACEFS: testInfo.outputPath('no-tracefs') });
  expect(nowhere.error).toMatch(/no tracefs/);
  // the pure rule: the fields, named, for each way a record can be incomplete
  const failing = { status: 'timedOut', frozen: false, captureFile: null, browserGone: false };
  expect(await missingEvidence({ ...failing, flight: null }, { CI: 'true' })).toEqual([expect.stringMatching(/^flight recorder/)]);
  expect(await missingEvidence({ ...failing, flight: { kernel: { unavailable: 'ring off' }, browserTrace: { file: 'x' } } }, { CI: 'true' })).toEqual([expect.stringMatching(/^kernel ring \(ring off\)/)]);
  expect(await missingEvidence({ ...failing, flight: { kernel: { file: testInfo.outputPath('missing.gz') }, browserTrace: {} } }, { CI: 'true' })).toEqual([expect.stringMatching(/^kernel ring \(unreadable/), expect.stringMatching(/^browser trace/)]);
  expect(await missingEvidence({ ...failing, status: 'passed' }, { CI: 'true' }), 'a test that passed owes nothing').toEqual([]);
  expect(await missingEvidence({ ...failing, flight: null }, {}), 'a machine that does not record owes nothing').toEqual([]);
  // the real path: a test that timed out with the ring gone fails its teardown with the named field
  const own = await playwright.chromium.launch(launchOptions);
  const timedOut = new Proxy(testInfo, { get: (target, key) => (key === 'status' ? 'timedOut' : Reflect.get(target, key)) });
  const watch = makeWatch(own, timedOut);
  const instance = process.env[INSTANCE_VARIABLE];
  delete process.env[INSTANCE_VARIABLE];
  try {
    await expect(watch.stop()).rejects.toThrow(/^EVIDENCE MISSING: kernel ring \(the kernel ring did not start/);
  } finally {
    process.env[INSTANCE_VARIABLE] = instance;
    await own.close();
  }
});

test('a test that fails with nothing frozen leaves the rings anyway, and the rings go on for the tests after it', async ({ playwright, launchOptions }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  const own = await playwright.chromium.launch(launchOptions);
  const failed = new Proxy(testInfo, { get: (target, key) => (key === 'status' ? 'failed' : Reflect.get(target, key)) });
  const watch = makeWatch(own, failed);
  try {
    const context = await own.newContext();
    await context.newPage();
    await watch.stop();   // does not throw: the record is complete
    const names = readdirSync(testInfo.outputDir);
    expect(names).toEqual(expect.arrayContaining(['flight-failed-kernel.txt.gz', 'flight-failed-browser-trace.json.gz']));
    expect((await ringState()).on, 'the ring records on').toBe('1');
  } finally { await own.close(); }
});

test('the watchdog, outside every worker and browser, sees a renderer frozen in an untimed futex wait and writes it out', async ({ page, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  test.setTimeout(testInfo.timeout + NATIVE_MOST_MS);
  const out = testInfo.outputPath('watchdog');
  const watchdog = startWatchdog(process.env[INSTANCE_VARIABLE], process.env, out, 4000);
  const hang = await hangPage(page, stallWatch);
  try {
    await expect.poll(() => (existsSync(out) ? readdirSync(out).filter((name) => /^watchdog-\d+-\d+-\d+\.json$/.test(name)) : []), { timeout: 60000 }).not.toEqual([]);
    const report = JSON.parse(readFileSync(join(out, readdirSync(out).find((name) => /^watchdog-\d+-\d+-\d+\.json$/.test(name))), 'utf8'));
    expect(report.reason).toMatch(/untimed futex wait/);
    expect(report.futex.untimed).toBe(true);
    expect(report.futex.memory.bytes, JSON.stringify(report.futex.memory)).toMatch(/^[0-9a-f]{128}$/);
    expect(report.threads.length).toBeGreaterThan(1);
    expect(report.threads.some((thread) => /\b202 0x[0-9a-f]+ 0x189\b/.test(thread.syscall))).toBe(true);
    expect(report.kernelRing.file, JSON.stringify(report.kernelRing)).toBeTruthy();
    expect(report.futex.ring.waiter.lastWait.untimed).toBe(true);
    expect(report.processes.some((each) => /--type=renderer/.test(each.cmdline))).toBe(true);
  } finally {
    hang.release();
    stopWatchdog(watchdog);
    await resumeKernel();
  }
});

test('a stall of the machine, seen from inside: a tick that comes late is kept with the steal time that passed', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const out = testInfo.outputPath('host-stalls');
  const dog = new Watchdog({ root: process.pid, out, gapMs: 300 });
  let now = 1000;
  dog.tick(now);
  now += 100; dog.tick(now);
  now += 100 + 1800; dog.tick(now);   // nothing ran for 1.8 s: every task of the machine stood still
  expect(dog.stalls.length).toBe(1);
  expect(dog.stalls[0].gapMs).toBe(1800);
  expect(dog.stalls[0].stealMsDuring).toBeGreaterThanOrEqual(0);
  const file = JSON.parse(readFileSync(join(out, `host-stalls-${process.pid}-${process.pid}.json`), 'utf8'));
  expect(file[0].gapMs).toBe(1800);
  // and a real one: a loop that keeps this process from its timers for 1.2 s is seen by a timer of the same process
  const real = new Watchdog({ root: process.pid, out: testInfo.outputPath('real'), gapMs: 300 });
  const timer = setInterval(() => real.tick(Date.now()), 100);
  await new Promise((resolve) => setTimeout(resolve, 400));
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 1200);
  await new Promise((resolve) => setTimeout(resolve, 400));
  clearInterval(timer);
  expect(real.stalls.some((each) => each.gapMs >= 900)).toBe(true);
});

test('the job-level check names the missing field of a report, and finds a timeout that left no record at all', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const report = (status, message) => ({ suites: [{ specs: [{ title: 'a test', file: 'a.spec.js', tests: [{ results: [{ status, errors: message ? [{ message }] : [] }] }] }] }] });
  expect(missingFields([report('failed', 'Error: EVIDENCE MISSING: kernel ring (not written)\n at x')], [])).toEqual(['kernel ring (not written) (test: a test)']);
  expect(missingFields([report('timedOut', 'Test timeout of 90000ms exceeded')], [])[0]).toMatch(/^kernel ring \(1 test\(s\) timed out and no test left a flight record/);
  expect(missingFields([report('passed')], [])).toEqual([]);
  const kept = testInfo.outputPath('flight-1-kernel.txt.gz');
  writeFileSync(kept, 'x');
  expect(missingFields([report('timedOut', 'Test timeout')], [kept])).toEqual([]);
});
