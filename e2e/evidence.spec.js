/**
 * Completeness of the evidence (#575), proved by induced faults: for each class of failure the table on quire#575
 * lists, a test makes it happen on purpose and asserts that the artifact holds the field that identifies it. Where the
 * class is not this suite's to cause (a hypervisor stall, memory corruption), the test induces what the substitute
 * observes. The recorder must be on (CI, or QUIRE_FLIGHT=1 with sudo): these tests prove what it lands. Keyword: evidence.
 */

import { createServer } from 'node:http';
import { Worker } from 'node:worker_threads';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';
import { closeSync, existsSync, mkdirSync, openSync, readdirSync, readFileSync, renameSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { execFile, spawn, spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { createReadStream, createWriteStream } from 'node:fs';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { createGunzip, createGzip, gunzipSync } from 'node:zlib';
import { createInterface } from 'node:readline';
import { test, expect } from './fixtures.js';
import { arm, capture, CAPTURE_MOST_MS, NATIVE_MOST_MS, stallWatch as makeWatch } from './stall-capture.js';
import { capabilities, diskEvidence, missingEvidence, pageState, parseBlocked, symbolEvidence } from './evidence.js';
import { pixelDiff } from './relaunch.js';
import { missingFields } from './evidence-check.js';
import { futexAnalysis, ringContent } from './flight-recorder.js';
import { INSTANCE_VARIABLE, OUT_VARIABLE, keepBoth, keepKernel, pauseInstance, readSyscall, ringSeen, ringState, ringStats, startKernel, startWatchdog, stopKernel, stopWatchdog, wanted } from './flight-recorder.js';
import { Watchdog } from './flight-watchdog.js';
import { LOCK_NAME, LOCK_UNREADABLE_MS, lockFailuresIn, segmentsIn, withRingLock } from './flight-tracefs.js';
import { COST_FILE } from './preflight.js';

function desktopOnly(testInfo) {
  test.skip(testInfo.project.name !== 'desktop', 'the renderer and the machine do not depend on the project: once, in desktop, is enough');
}

/** The recorder is on: these tests prove what it records, so a run without it fails here, saying how to turn it on. */
async function recorderOn() {
  expect(wanted(), 'run with CI=true or QUIRE_FLIGHT=1 (and sudo): the evidence tests prove what the recorder lands').toBe(true);
  expect(process.env[INSTANCE_VARIABLE], 'the kernel ring started in global setup').toBeTruthy();
  // no capture stops the ring (ring snapshot, #910), so there is nothing to start again here
}

// a ring is read a line at a time (ringSeen): one that recorded a whole run is larger than a string can be
const ringHas = async (file, patterns) => ringSeen(file, patterns);
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
  expect((await ringHas(found.flight.kernel.file, { switched: /sched_switch/ })).switched, 'the ring holds the scheduler').not.toBeNull();
  // Chrome's trace holds the renderer's own events
  const trace = JSON.parse(gunzipSync(readFileSync(found.flight.browserTrace.file)).toString());
  expect((trace.traceEvents || trace).some((event) => event.pid === word.pid)).toBe(true);
  // the frames: named, or unavailable with the reason and the module and offset of each frame to resolve them later
  // the frames: some are named and some are not; for the ones that are not, why, and the module and offset of each (always asserted:
  // on the runner 5 of 7 main-thread frames are named, and the unnamed ones are what an offline lookup takes)
  const symbols = found.symbols.find((each) => each.pid === word.pid);
  expect(symbols.buildId).toMatch(/^[0-9a-f]{40}$/);
  expect(symbols.frames).toBeGreaterThan(symbols.named);
  expect(symbols.unnamed.length, 'the frames without a name are listed').toBe(Math.min(symbols.frames - symbols.named, 20));
  expect(symbols.unnamed[0].module).toBeTruthy();
  expect(symbols.unnamed[0].offset).toMatch(/^0x[0-9a-f]+$/);
  expect(symbols.state).toMatch(/^(unavailable: .*build id [0-9a-f]{40}|debug file found: |named by the binary)/);
  // the registers of the wait, and the traffic: Chrome's trace names the Mojo interfaces and the ring the sockets (G1 and G4 of #575)
  expect(word.registers.sp).toMatch(/^0x[0-9a-f]+$/);
  expect(new Set(trace.traceEvents ? trace.traceEvents.map((event) => event.cat) : trace.map((event) => event.cat)).size).toBeGreaterThan(2);
  expect((await ringHas(found.flight.kernel.file, { traffic: /sys_(recvmsg|sendmsg|epoll_pwait)/ })).traffic, 'the ring holds the Mojo traffic').not.toBeNull();
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
  const seenGone = await ringHas(stallWatch.state.flight.kernel.file, { gone: new RegExp(`(signal_generate: sig=11 .*pid=(${gone.join('|')}) )|(sched_process_exit: .*pid=(${gone.join('|')}) )`) });
  expect(seenGone.gone, 'the signal or the exit of the renderer is in the ring').not.toBeNull();
  const written = readdirSync(testInfo.outputDir).filter((name) => /^crash-\d+\.json$/.test(name));
  expect(written.length).toBeGreaterThan(0);
  const body = JSON.parse(readFileSync(join(testInfo.outputDir, written[0]), 'utf8'));
  expect(body.reason).toMatch(/crashed/);
  expect(body.kernelLog).toBeTruthy();
  expect(body.flight.browserTrace.file, 'the browser lived, so its trace is there').toBeTruthy();
  await context.close();
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
    const seenBrowser = await ringHas(watch.state.flight.kernel.file, { signal: new RegExp(`signal_generate: sig=11 .*pid=${browserPid} `), exit: new RegExp(`sched_process_exit: .*pid=${browserPid} `) });
    expect(seenBrowser.signal, 'the signal is in the ring').not.toBeNull();
    expect(seenBrowser.exit, 'the exit is in the ring').not.toBeNull();
    expect(watch.state.browserGone).toBe(true);
    expect(watch.state.flight.browserTrace.unavailable || watch.state.flight.browserTrace.error, 'the missing trace says why').toBeTruthy();
    expect(await watch.verify(), 'a dead browser needs no trace').toEqual([]);
  } finally {
    await watch.stop();
    await own.close().catch(() => {});
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
    const kernel = await keepKernel(testInfo.outputPath('disk-ring.txt.gz'));
    expect(kernel.error, JSON.stringify(kernel)).toBeUndefined();
    expect((await ringHas(kernel.file, { block: /block_rq_issue/ })).block, 'the ring holds the block requests').not.toBeNull();
  } finally {
    if (kept === undefined) delete process.env.QUIRE_EVIDENCE_PATHS; else process.env.QUIRE_EVIDENCE_PATHS = kept;
    spawnSync(...(root ? ['umount', [mountpoint]] : ['sudo', ['-n', 'umount', mountpoint]]), { encoding: 'utf8' });
  }
});

test('a ring larger than a string can be (a whole run recorded, as the segments of several captures) is read a line at a time by every reader', async ({}, testInfo) => {
  test.setTimeout(testInfo.timeout + 240000);
  const file = testInfo.outputPath('huge-ring.txt.gz');
  const line = `   Compositor-4242  [001] .... 1000.000001: sys_enter_futex: ${'x'.repeat(900)}\n`;
  // the file of a capture is the gzip members of the segments before it and then its own snapshot (flight-tracefs.js, ring snapshot): two members here.
  // 640 million characters in all: past the 0x1fffffe8 a string can hold, which the first CI run met with a ring of a whole run
  const segment = (events, extra) => Readable.from((function* () {
    yield `# entries-in-buffer/entries-written: ${events}/${events}   #P:4\n# the snapshot of the ring taken for this capture; clock: mono\n`;
    for (let i = 0; i < events; i += 1) yield line;
    yield extra;
  })());
  // the wait of the thread is in the earlier segment, the last event in the later one
  await pipeline(segment(350000, '   Compositor-4242  [001] .... 999.5: sys_futex(uaddr: 0x7ffe33dd6610, op: 0x189, val: 0x0, utime: 0x0, uaddr2: 0x0, val3: 0x0)\n'), createGzip({ level: 1 }), createWriteStream(file));
  await pipeline(segment(350000, '   Chrome_ChildIOT-4243  [002] .... 1000.5: sched_process_exit: comm=last pid=4243 prio=120\n'), createGzip({ level: 1 }), createWriteStream(file, { flags: 'a' }));
  expect(() => gunzipSync(readFileSync(file)).toString(), 'the failure of the first run, reproduced: one string of the whole ring').toThrow(/string longer than|Invalid string length|Cannot create a string/);
  const seen = await ringSeen(file, { header: /entries-in-buffer/, last: /sched_process_exit: comm=last/ });
  expect(seen.header).not.toBeNull();
  expect(seen.last, 'the last line of a ring larger than a string, in its last member').not.toBeNull();
  expect((await ringContent(file)).ok).toBe(true);
  const analysed = await futexAnalysis(file, { address: '7ffe33dd6610', tid: 4242 });
  expect(analysed && analysed.error, JSON.stringify(analysed).slice(0, 300)).toBeUndefined();
  expect(analysed.waiter.lastWait && analysed.waiter.lastWait.untimed, 'the wait of the earlier member is read').toBe(true);
  expect(analysed.ringEnd, 'and the reading goes on to the last member').toBe(1000.5);
});

test('the ring is read in both forms the kernel prints a futex call in (6.18 with 0x, 7.0 on the runners without)', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const { gzipSync } = await import('node:zlib');
  for (const [name, call, wake] of [
    ['with 0x', 'sys_futex(uaddr: 0x7ffe33dd6610, op: 0x189, val: 0, utime: 0, uaddr2: 0, val3: 0xffffffff)', 'sys_futex(uaddr: 0x7ffe33dd6610, op: 0x81, val: 1, utime: 0, uaddr2: 0, val3: 0)'],
    ['without', 'sys_futex(uaddr: 7ffe33dd6610, op: 189, val: 0, utime: 0, uaddr2: 0, val3: ffffffff)', 'sys_futex(uaddr: 7ffe33dd6610, op: 81, val: 1, utime: 0, uaddr2: 0, val3: 0)'],
  ]) {
    const file = testInfo.outputPath(`ring-${name.replace(' ', '-')}.txt.gz`);
    writeFileSync(file, gzipSync([
      '# entries-in-buffer/entries-written: 4/4   #P:4',
      `  chrome-headless-3289    [003] .....   239.953428: ${call}`,
      `  Chrome_ChildIOT-3293    [001] .....   241.000000: ${wake}`,
      '  Chrome_ChildIOT-3293    [001] d....   241.000100: sched_wakeup: comm=chrome-headless pid=3289 prio=120 target_cpu=003',
      '  chrome-headless-3289    [003] d....   250.000000: sched_switch: prev_comm=chrome-headless prev_pid=3289 prev_prio=120 prev_state=S ==> next_comm=swapper/3 next_pid=0 next_prio=120',
    ].join('\n')));
    const { futexAnalysis } = await import('./flight-recorder.js');
    const found = await futexAnalysis(file, { address: '7ffe33dd6610', tid: 3289 });
    expect(found.waiter.lastWait, name).toMatchObject({ untimed: true, kind: 'wait' });
    expect(found.onAddress.wakers.map((each) => each.task), name).toEqual(['Chrome_ChildIOT']);
    expect(found.waiter.wokenLast.by, name).toBe('Chrome_ChildIOT-3293');
    expect(found.waiter.sleepingMs, name).toBe(0);
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

test('a recorder that does not start is said, and the rule that names what a red is missing', async ({}, testInfo) => {
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
  // a test that cuts the native step of the capture on purpose ('native step') does not owe that step's fields, and owes both rings as any red does;
  // one that cuts the whole capture ('whole capture') owes nothing of it
  const ring = testInfo.outputPath('ring.txt.gz');
  writeFileSync(ring, (await import('node:zlib')).gzipSync('# tracer: nop\n# entries-in-buffer/entries-written: 1/1   #P:4\n  task-1 [000] d.... 1.000000: sched_switch: x\n'));
  const cut = { status: 'passed', expectedStatus: 'passed', frozen: true, captureFile: null, browserGone: false, captureResult: { futex: [{ pid: 7, notInFutex: 'no kernel view of the main thread' }] } };
  const rings = { kernel: { file: ring }, browserTrace: { file: 'x' } };
  expect(await missingEvidence({ ...cut, flight: rings }, { CI: 'true' }), 'without the exemption the native step\'s fields are owed').toEqual(['kernel view of renderer 7', 'stall capture']);
  expect(await missingEvidence({ ...cut, cutOnPurpose: true, flight: rings }, { CI: 'true' }), 'a value that is neither kind of cut is no exemption').toEqual(['kernel view of renderer 7', 'stall capture']);
  expect(await missingEvidence({ ...cut, cutOnPurpose: 'whole capture', flight: null }, { CI: 'true' }), 'a capture cut whole owes nothing').toEqual([]);
  expect(await missingEvidence({ ...cut, cutOnPurpose: 'native step', flight: rings }, { CI: 'true' }), 'the native step\'s fields are not owed').toEqual([]);
  expect(await missingEvidence({ ...cut, cutOnPurpose: 'native step', flight: { kernel: { unavailable: 'ring off' }, browserTrace: { file: 'x' } } }, { CI: 'true' }), 'the kernel ring is owed').toEqual([expect.stringMatching(/^kernel ring \(ring off\)/)]);
  expect(await missingEvidence({ ...cut, cutOnPurpose: 'native step', flight: { kernel: { file: ring }, browserTrace: {} } }, { CI: 'true' }), 'the browser trace is owed').toEqual([expect.stringMatching(/^browser trace/)]);
  expect(await missingEvidence({ ...cut, cutOnPurpose: 'native step', flight: null }, { CI: 'true' }), 'a record at all is owed').toEqual([expect.stringMatching(/^flight recorder/)]);
});
test('the watchdog, outside every worker and browser, sees a renderer frozen in an untimed futex wait and writes it out', async ({ page, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  test.setTimeout(testInfo.timeout + NATIVE_MOST_MS + 120000);
  const out = testInfo.outputPath('watchdog');
  const watchdog = startWatchdog(process.env[INSTANCE_VARIABLE], process.env, out, 4000);
  const hang = await hangPage(page, stallWatch);
  try {
    // a report is whole when it parses (the file is written again once the stacks are in)
    const reports = () => (existsSync(out) ? readdirSync(out).filter((name) => /^watchdog-\d+-\d+-\d+\.json$/.test(name)).flatMap((name) => { try { return [JSON.parse(readFileSync(join(out, name), 'utf8'))]; } catch (partial) { return []; } }) : []);
    await expect.poll(() => reports().length, { timeout: 150000 }).toBeGreaterThan(0);
    const report = reports()[0];
    expect(report.reason).toMatch(/untimed wait \(futex\)/);
    expect(report.futex.untimed).toBe(true);
    expect(report.futex.memory.bytes, JSON.stringify(report.futex.memory)).toMatch(/^[0-9a-f]{128}$/);
    expect(report.threads.length).toBeGreaterThan(1);
    expect(report.threads.some((thread) => /\b202 0x[0-9a-f]+ 0x189\b/.test(thread.syscall))).toBe(true);
    expect(report.kernelRing.file, JSON.stringify(report.kernelRing)).toBeTruthy();
    expect(report.futex.ring.waiter.lastWait.untimed).toBe(true);
    expect(report.processes.some((each) => /--type=renderer/.test(each.cmdline))).toBe(true);
    // the stall watch sees the same freeze (its capture begins about 5 s into the hang, in the Playwright worker) and is not cut short by this
    // test ending: the hang is held until that capture has read the renderer, as the test above does (a loaded run ended the test under it, quire#575)
    await stallWatch.next(page, 20000 + NATIVE_MOST_MS);
  } finally {
    hang.release();
    stopWatchdog(watchdog);
  }
});

test('a page closed while the stall watch is still capturing its frozen renderer: the capture reads the renderer before it goes (quire#575)', async ({ page, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  test.setTimeout(testInfo.timeout + NATIVE_MOST_MS);
  const hang = await hangPage(page, stallWatch);
  try {
    await stallWatch.started(page, 20000);
    // past the capture's questions to the page (they are answered or timed out within 4 s, the renderers' CPU read in 1 s more): it is in the rings now, and the test ends under it
    await new Promise((resolve) => setTimeout(resolve, 5500));
  } finally { hang.release(); }
});

test('a renderer gone when the capture has finished its rings: what /proc held of it was read before them (quire#575, capture before close)', async ({ playwright, launchOptions }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  test.setTimeout(testInfo.timeout + CAPTURE_MOST_MS + NATIVE_MOST_MS);
  const own = await playwright.chromium.launch(launchOptions);
  try {
    const page = await (await own.newContext()).newPage();
    const armed = await arm(page);
    const hang = await hangPage(page, { session: async () => armed.session });
    try {
      // the rings are the step after which a context that closes under the capture has taken the renderers (on a runner they take longer than the
      // test): here the step kills every renderer and returns when /proc has lost them, so the capture reads what is left after the rings, every run
      const rings = async () => {
        for (const each of (await processes(own)).filter((process) => process.type === 'renderer')) process.kill(each.id, 'SIGKILL');
        await expect.poll(() => (processes(own).then((list) => list.filter((process) => process.type === 'renderer' && existsSync(`/proc/${process.id}`)).length)), { timeout: 20000 }).toBe(0);
        return { rings: 'killed' };
      };
      await new Promise((resolve) => setTimeout(resolve, 500));
      const found = await capture(page, armed, 'induced: a renderer gone after the rings', own, () => {}, undefined, null, rings);
      const word = (found.futex || []).find((each) => each.untimed);
      expect(word, `a renderer waited in an untimed futex: ${JSON.stringify(found.futex)}`).toBeTruthy();
      expect(word.memory.bytes, JSON.stringify(word.memory)).toMatch(/^[0-9a-f]{128}$/);
      const waiting = found.rendererCpu.find((each) => each.pid === word.pid);
      expect(waiting.threads.join(' '), 'the threads were read').not.toMatch(/ENOENT/);
      expect(waiting.mainThread.syscall, 'the main thread was read').toMatch(/^202 /);
      expect(waiting.channels.join(' '), 'the open files were read').not.toMatch(/ENOENT/);
      expect(found.native.renderers.find((each) => each.pid === word.pid).kernel.tasks.length, 'the kernel view was read').toBeGreaterThan(1);
    } finally { hang.release(); }
  } finally { await own.close().catch(() => {}); }
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

test('the watchdog counts the CPU of the main thread, not of the process: a frozen renderer whose other threads tick now and then is still reported', async ({}, testInfo) => {
  desktopOnly(testInfo);
  // a /proc of its own: the runner (100) and its renderer (200), the main thread waiting in an untimed futex
  const proc = testInfo.outputPath('proc');
  const stat = (pid, parent, comm, user, system) => `${pid} (${comm}) S ${parent} 0 0 0 0 0 0 0 0 0 ${user} ${system} 0 0 20 0 1 0 0\n`;
  const lay = (pid, parent, comm, cmdline, processTicks, mainTicks, syscall) => {
    mkdirSync(join(proc, String(pid), 'task', String(pid)), { recursive: true });
    writeFileSync(join(proc, String(pid), 'stat'), stat(pid, parent, comm, processTicks, 0));
    writeFileSync(join(proc, String(pid), 'cmdline'), cmdline.replace(/ /g, '\0'));
    writeFileSync(join(proc, String(pid), 'task', String(pid), 'stat'), stat(pid, parent, comm, mainTicks, 0));
    writeFileSync(join(proc, String(pid), 'task', String(pid), 'syscall'), syscall);
  };
  const futex = '202 0x7ffe9ead5e30 0x189 0x0 0x0 0x0 0xffffffff 0x7ffe9ead5ba0 0x7fdeb3e98e51\n';
  lay(100, 1, 'node', 'node runner', 5, 5, '0 0x0\n');
  lay(200, 100, 'chrome', 'chrome --type=renderer', 40, 12, futex);
  const out = testInfo.outputPath('reports');
  const dog = new Watchdog({ root: 100, out, proc, sustainMs: 10000, stacks: false });
  expect(await dog.scan(0)).toEqual([]);
  // a thread other than the main one uses a tick; the main thread uses none
  lay(200, 100, 'chrome', 'chrome --type=renderer', 41, 12, futex);
  expect(await dog.scan(5000)).toEqual([]);
  lay(200, 100, 'chrome', 'chrome --type=renderer', 42, 12, futex);
  const written = await dog.scan(11000);
  expect(written, 'the main thread used no CPU for 11 s').toHaveLength(1);
  const report = JSON.parse(readFileSync(join(out, written[0]), 'utf8'));
  expect(report.reason).toMatch(/process 200: the main thread has been in an untimed wait \(futex\) with no CPU used for 11000 ms/);
  // and a main thread that does use CPU starts the clock again
  const busy = new Watchdog({ root: 100, out: testInfo.outputPath('busy'), proc, sustainMs: 10000, stacks: false });
  await busy.scan(0);
  lay(200, 100, 'chrome', 'chrome --type=renderer', 50, 13, futex);
  await busy.scan(5000);
  expect(await busy.scan(11000), 'the main thread used a tick at 5 s: 6 s since').toEqual([]);
});

test('a watchdog run under sudo gives its output to the invoking user: the directories it makes, the heartbeat, a stall and a report (quire#767)', async ({}, testInfo) => {
  desktopOnly(testInfo);
  // sudo runs the watchdog as root, so what it writes is root's unless it is given to SUDO_UID; the invoking ids must differ from the process's own, or the code
  // that gives nothing over passes: as root they are nobody's, else the own uid and another group of the process's (a chown it may do), and without a second group the test cannot tell
  const other = process.getgroups().find((group) => group !== process.getgid());
  test.skip(process.getuid() !== 0 && other === undefined, 'a non-root user with one group cannot be given a different group to chown to');
  const invoking = process.getuid() === 0 ? { uid: 65534, gid: 65534 } : { uid: process.getuid(), gid: other };
  expect(invoking.uid !== process.getuid() || invoking.gid !== process.getgid(), 'the invoking ids differ from the process\'s own').toBe(true);
  const proc = testInfo.outputPath('proc');
  const lay = (pid, parent, comm, cmdline, syscall) => {
    mkdirSync(join(proc, String(pid), 'task', String(pid)), { recursive: true });
    const stat = `${pid} (${comm}) S ${parent} 0 0 0 0 0 0 0 0 0 5 5 0 0 20 0 1 0 0\n`;
    writeFileSync(join(proc, String(pid), 'stat'), stat);
    writeFileSync(join(proc, String(pid), 'cmdline'), cmdline.replace(/ /g, '\0'));
    writeFileSync(join(proc, String(pid), 'task', String(pid), 'stat'), stat);
    writeFileSync(join(proc, String(pid), 'task', String(pid), 'syscall'), syscall);
  };
  lay(100, 1, 'node', 'node runner', '0 0x0\n');
  lay(200, 100, 'chrome', 'chrome --type=renderer', '202 0x7ffe9ead5e30 0x189 0x0 0x0 0x0 0xffffffff 0x7ffe9ead5ba0 0x7fdeb3e98e51\n');
  const base = testInfo.outputPath('owned');
  const out = join(base, 'flight', 'watchdog');
  const dog = new Watchdog({ root: 100, out, proc, sustainMs: 10000, stacks: false, env: { SUDO_UID: String(invoking.uid), SUDO_GID: String(invoking.gid) } });
  dog.tick(0, 0);
  dog.tick(2000, 2000);                 // a tick 1.9 s late: host-stalls is written
  dog.heartbeat();
  expect(await dog.scan(0)).toEqual([]);
  expect(await dog.scan(11000), 'the frozen renderer is reported').toHaveLength(1);
  const names = readdirSync(out);
  expect(names, 'the heartbeat, the stall and the report are there').toEqual(expect.arrayContaining([
    expect.stringMatching(/^heartbeat-100-\d+\.json$/), expect.stringMatching(/^host-stalls-100-\d+\.json$/), expect.stringMatching(/^watchdog-100-\d+-1\.json$/),
  ]));
  const made = [base, join(base, 'flight'), out, ...names.map((name) => join(out, name))];
  for (const path of made) {
    const info = statSync(path);
    expect({ path, uid: info.uid, gid: info.gid }).toEqual({ path, uid: invoking.uid, gid: invoking.gid });
  }
});

test('a chown that fails does not stop the watchdog\'s own output: the report is written whole and the failure is in its log, and the tree is walked only when a file came (quire#767)', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const proc = testInfo.outputPath('proc');
  const lay = (pid, parent, comm, cmdline, syscall) => {
    mkdirSync(join(proc, String(pid), 'task', String(pid)), { recursive: true });
    const stat = `${pid} (${comm}) S ${parent} 0 0 0 0 0 0 0 0 0 5 5 0 0 20 0 1 0 0\n`;
    writeFileSync(join(proc, String(pid), 'stat'), stat);
    writeFileSync(join(proc, String(pid), 'cmdline'), cmdline.replace(/ /g, '\0'));
    writeFileSync(join(proc, String(pid), 'task', String(pid), 'stat'), stat);
    writeFileSync(join(proc, String(pid), 'task', String(pid), 'syscall'), syscall);
  };
  lay(100, 1, 'node', 'node runner', '0 0x0\n');
  lay(200, 100, 'chrome', 'chrome --type=renderer', '202 0x7ffe9ead5e30 0x189 0x0 0x0 0x0 0xffffffff 0x7ffe9ead5ba0 0x7fdeb3e98e51\n');
  const out = testInfo.outputPath('refused');
  const refused = [];
  const chown = (path) => { refused.push(path); const error = new Error(`EPERM: operation not permitted, chown '${path}'`); error.code = 'EPERM'; throw error; };
  const said = [];
  const write = console.error;
  console.error = (...line) => said.push(line.join(' '));
  let dog;
  let written;
  try {
    dog = new Watchdog({ root: 100, out, proc, sustainMs: 10000, stacks: false, chown, env: { SUDO_UID: '65534', SUDO_GID: '65534' } });
    dog.tick(0, 0);
    dog.tick(2000, 2000);                 // host-stalls is written, and its chown is refused
    dog.heartbeat();
    await dog.scan(0);
    written = await dog.scan(11000);
  } finally { console.error = write; }
  expect(written, 'the report is written although every chown is refused').toHaveLength(1);
  const report = JSON.parse(readFileSync(join(out, written[0]), 'utf8'));
  expect(report.reason, 'and whole').toMatch(/process 200: the main thread has been in an untimed wait/);
  expect(readdirSync(out), 'with the heartbeat and the stall').toEqual(expect.arrayContaining([expect.stringMatching(/^heartbeat-100-\d+\.json$/), expect.stringMatching(/^host-stalls-100-\d+\.json$/)]));
  expect(dog.ownFailures.length, 'the failures are kept').toBeGreaterThan(0);
  expect(dog.ownFailures[0]).toMatchObject({ code: 'EPERM' });
  expect(refused.length).toBeGreaterThan(0);
  expect(said.join('\n'), 'and said in the watchdog\'s log').toMatch(/^\[watchdog\] could not give .* to 65534:65534: EPERM /m);
  // the tree is walked when a file came, not at every heartbeat
  const quiet = new Watchdog({ root: 100, out: testInfo.outputPath('quiet'), proc, sustainMs: 10000, stacks: false, env: { SUDO_UID: '65534', SUDO_GID: '65534' }, chown: () => {} });
  quiet.heartbeat();
  const walked = quiet.walks;
  for (let beat = 0; beat < 5; beat += 1) quiet.heartbeat();
  expect(quiet.walks, 'five more heartbeats of the same file walk nothing').toBe(walked);
  quiet.tick(0, 0);
  quiet.tick(2000, 2000);
  expect(quiet.walks, 'a stall file written is walked').toBe(walked + 1);
});

test('a chown that fails for good is said once for its path and kept in a bounded list across heartbeats (quire#767)', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const said = [];
  const write = console.error;
  console.error = (...line) => said.push(line.join(' '));
  let dog;
  try {
    // files are refused for good, directories are given over, so the walk reaches every file
    const chown = (path) => { if (!/\.(json|part)$/.test(path)) return; const error = new Error(`EPERM: operation not permitted, chown '${path}'`); error.code = 'EPERM'; throw error; };
    dog = new Watchdog({ root: 100, out: testInfo.outputPath('permanent'), proc: testInfo.outputPath('noproc'), stacks: false, chown, env: { SUDO_UID: '65534', SUDO_GID: '65534' } });
    for (let beat = 0; beat < 5; beat += 1) dog.heartbeat();
    // many distinct paths: the list stops at the cap
    for (let file = 0; file < 150; file += 1) { writeFileSync(join(dog.out, `extra-${file}.json`), '{}'); dog.own(dog.out); }
  } finally { console.error = write; }
  const heartbeatLines = said.filter((line) => /heartbeat-100-\d+\.json\.part/.test(line));
  expect(heartbeatLines, 'the heartbeat file is said once over five heartbeats').toHaveLength(1);
  expect(dog.ownFailures.length, 'the list is bounded').toBe(100);
  expect(said.length, 'each path is said once').toBe(new Set(said).size);
});

test('a ring lock that cannot be had in its limit leaves a record, runs the action, and is the job\'s failure', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const dir = testInfo.outputPath('lock');
  mkdirSync(dir, { recursive: true });
  // another capture holds the lock, and renewed it just now: it is not stale, so it is waited for until the limit
  writeFileSync(join(dir, LOCK_NAME), `${new Date().toISOString()} 4242\n`);
  const began = Date.now();
  const said = [];
  const write = console.error;
  console.error = (...line) => said.push(line.join(' '));
  let ran;
  try { ran = withRingLock(dir, () => 'ran', { most: 300, stale: 60000 }); } finally { console.error = write; }
  expect(ran, 'the action runs without the lock').toBe('ran');
  expect(Date.now() - began, 'it waited for the limit and no longer').toBeGreaterThanOrEqual(290);
  const records = lockFailuresIn(dir);
  expect(records).toHaveLength(1);
  expect(records[0].text).toMatch(/did not get the ring lock in \d+ ms \(limit 300 ms; the lock said: .* 4242\)/);
  expect(said.join('\n'), 'and a line says so').toMatch(/^\[ring lock\] .*did not get the ring lock/);
  expect(existsSync(join(dir, LOCK_NAME)), 'the other holder\'s lock is not taken down').toBe(true);
  // the job-level check names it, with no report needed to hold it
  const unlocked = lockFailuresIn(dir).map((each) => `ring lock (${each.text})`);
  expect(missingFields([], [], { unlocked })[0]).toMatch(/^ring lock \(.*did not get the ring lock/);
  // and a lock that is free is had at once, with no record
  const free = testInfo.outputPath('free');
  mkdirSync(free, { recursive: true });
  expect(withRingLock(free, () => 'ran', { most: 300 })).toBe('ran');
  expect(lockFailuresIn(free)).toEqual([]);
  expect(existsSync(join(free, LOCK_NAME)), 'and given back').toBe(false);
});

test('a ring lock that is empty, is not a time, or is older than the stale limit is taken; a live one is refused (ring lock, unreadable lock)', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const limits = { most: 1500, stale: 60000 };
  const taken = (name, content) => {
    const dir = testInfo.outputPath(name);
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, LOCK_NAME), content);
    const result = { ran: withRingLock(dir, () => 'ran', limits), records: lockFailuresIn(dir) };
    return { ...result, left: existsSync(join(dir, LOCK_NAME)) };
  };
  // a run that hit ENOSPC while writing the lock leaves it empty
  expect.soft(taken('empty', ''), 'an empty lock is taken, with no record').toEqual({ ran: 'ran', records: [], left: false });
  expect.soft(taken('text', 'not-a-time 99\n'), 'a lock with text that is not a number is taken').toEqual({ ran: 'ran', records: [], left: false });
  const old = new Date(Date.now() - 120000).toISOString();
  expect.soft(taken('old', `${old} 4242\n`), 'a lock older than the stale limit is taken').toEqual({ ran: 'ran', records: [], left: false });
  // a live lock (younger than the limit) is still refused: the limit passes, a record is left, and the lock stays
  const write = console.error;
  console.error = () => {};
  let refused;
  try {
    const dir = testInfo.outputPath('live-again');
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, LOCK_NAME), `${new Date().toISOString()} 4242\n`);
    refused = { ran: withRingLock(dir, () => 'ran', { most: 300, stale: 60000 }), records: lockFailuresIn(dir), left: existsSync(join(dir, LOCK_NAME)) };
  } finally { console.error = write; }
  expect(refused.ran, 'the action still runs').toBe('ran');
  expect(refused.records, 'a live lock is not taken: a record says it was not had').toHaveLength(1);
  expect(refused.records[0].text).toMatch(/did not get the ring lock .*4242\)/);
  expect(refused.left, 'and the live holder\'s lock stays').toBe(true);
});

// The re-creation of the lock (ring lock): a file with the same content replaces it at one instant, so no instant has no lock; `gap` is called after the sibling is written and before the rename.
const recreateSource = `
function recreate(path, gap) {
  const before = statSync(path).ino; // the inode the filesystem may give again (ext4 and tmpfs do on the next file made)
  const text = readFileSync(path, 'utf8'); // the same content, so the content alone does not tell the two locks apart
  let reused = false;
  for (let tries = 0; tries < 1000 && !reused; tries++) { writeFileSync(path + '.next', text); gap(); renameSync(path + '.next', path); reused = statSync(path).ino === before; }
  return reused;
}
`;
// A live holder as another process plays it: `steps` is [[ms, 'write' | 'unlink', content]], from the moment the script starts, on the lock `path`.
const holderScript = `
const { writeFileSync, unlinkSync, renameSync, statSync, readFileSync } = require('node:fs');
${recreateSource}
const [path, steps] = [process.argv[1], JSON.parse(process.argv[2])];
const begun = Date.now();
for (const [ms, action, content] of steps) {
  while (Date.now() - begun < ms) { /* wait */ }
  if (action === 'write') writeFileSync(path, content.replace('NOW', new Date().toISOString() + ' ' + process.pid + '\\n'), content.startsWith('NEW') ? { flag: 'wx' } : {});
  else if (action === 'swap') { writeFileSync(path + '.next', content); renameSync(path + '.next', path); } // another holder's lock in the first one's place, at one instant
  else if (action === 'recreate') writeFileSync(path + '.reused', String(recreate(path, () => {})));
  else unlinkSync(path);
}
`;
const productionRecreate = new Function('require', `const { writeFileSync, unlinkSync, renameSync, statSync, readFileSync } = require('node:fs'); ${recreateSource} return recreate;`)(createRequire(import.meta.url));
// The step the holder had before (ring lock): the lock removed, then made again with an exclusive create, so the path is free between the two.
const unlinkThenCreate = (path, gap) => {
  const text = readFileSync(path, 'utf8');
  unlinkSync(path);
  gap();
  writeFileSync(path, text, { flag: 'wx' });
  return true;
};
const UNREADABLE_BRIEF_MS = 40; // a live holder's lock is empty this long: less than the window
const REPLACED_AT_MS = LOCK_UNREADABLE_MS - 50; // the first lock has been seen unreadable almost for the whole window when another holder's takes its place
const REPLACEMENT_VALID_AT_MS = REPLACED_AT_MS + 100; // the replacement is unreadable for this long, past the window of the first lock's timer but within its own
const REPLACEMENT_GIVEN_BACK_AT_MS = REPLACEMENT_VALID_AT_MS + 300;

const playHolder = (dir, steps) => {
  const path = join(dir, LOCK_NAME);
  const child = spawn(process.execPath, ['-e', holderScript, path, JSON.stringify(steps)], { stdio: 'inherit' });
  const closed = new Promise((resolve) => child.on('close', resolve));
  const waitUntil = Date.now() + 5000;
  while (!existsSync(path) && Date.now() < waitUntil) Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 1);
  return { began: Date.now(), closed };
};

test('a ring lock that is unreadable only briefly, or that another holder replaced while its timer ran, is not taken (ring lock, unreadable lock)', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const limits = { most: 3000, stale: 60000 };
  const outcome = async (name, steps) => {
    const dir = testInfo.outputPath(name);
    mkdirSync(dir, { recursive: true });
    const holder = playHolder(dir, steps);
    const ran = withRingLock(dir, () => ({ elapsed: Date.now() - holder.began, lockThere: existsSync(join(dir, LOCK_NAME)) }), limits);
    await holder.closed;
    return { ...ran, records: lockFailuresIn(dir) };
  };
  // a live holder that has made its lock and has not written it yet (empty for 40 ms): the waiter waits for its release
  const brief = await outcome('brief', [[0, 'write', 'NEW'], [UNREADABLE_BRIEF_MS, 'write', 'NOW'], [REPLACEMENT_GIVEN_BACK_AT_MS, 'unlink']]);
  expect.soft(brief.elapsed, 'a lock unreadable for less than the window is waited for, not taken').toBeGreaterThanOrEqual(REPLACEMENT_GIVEN_BACK_AT_MS - 50);
  expect.soft(brief.records, 'and no record').toEqual([]);
  // one unreadable lock is seen, given back, and another holder's lock begins unreadable: that is a new lock, its timer starts again
  const replaced = await outcome('replaced', [
    [0, 'write', 'NEW'],
    [REPLACED_AT_MS, 'swap', 'partial'], [REPLACEMENT_VALID_AT_MS, 'write', 'NOW'], [REPLACEMENT_GIVEN_BACK_AT_MS, 'unlink'],
  ]);
  expect.soft(replaced.elapsed, 'the other holder\'s lock is not taken down while it is live').toBeGreaterThanOrEqual(REPLACEMENT_GIVEN_BACK_AT_MS - 50);
  expect.soft(replaced.records, 'and no record').toEqual([]);
});

test('a waiter that takes the lock whenever it finds the path free is let in by the old re-creation and never by the new one (ring lock, unreadable lock)', async ({}, testInfo) => {
  desktopOnly(testInfo);
  // the waiter's move forced into the step's gap: the exact order of the failure, with no timing involved
  const play = (name, step) => {
    const dir = testInfo.outputPath(name);
    mkdirSync(dir, { recursive: true });
    const path = join(dir, LOCK_NAME);
    writeFileSync(path, `${new Date().toISOString()} 4242\n`);
    let took = 0;
    const waiter = () => { if (!existsSync(path)) { writeFileSync(path, 'taken\n', { flag: 'wx' }); took++; } };
    let error = 'none';
    try { step(path, waiter); } catch (failure) { error = failure.code; }
    return { took, error };
  };
  expect(play('old-step', unlinkThenCreate), 'the old step finds its lock taken: the exclusive create fails').toEqual({ took: 1, error: 'EEXIST' });
  expect(play('new-step', productionRecreate), 'the production step never leaves the path free').toEqual({ took: 0, error: 'none' });
});

test('a ring lock re-created with the same inode and still unreadable when the first one\'s window ends is not taken (ring lock, unreadable lock)', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const dir = testInfo.outputPath('recreated');
  mkdirSync(dir, { recursive: true });
  // the first holder's lock is unreadable and stays so; another holder removes it and makes its own at once (the same inode and content), which is unreadable
  // until its write: past the first lock's window, within its own
  const holder = playHolder(dir, [[0, 'write', 'NEW'], [REPLACED_AT_MS, 'recreate', ''], [REPLACEMENT_VALID_AT_MS, 'write', 'NOW'], [REPLACEMENT_GIVEN_BACK_AT_MS, 'unlink']]);
  const ran = withRingLock(dir, () => ({ elapsed: Date.now() - holder.began }), { most: 3000, stale: 60000 });
  await holder.closed;
  expect(readFileSync(join(dir, `${LOCK_NAME}.reused`), 'utf8'), 'the lock was made again with the inode of the first').toBe('true');
  expect.soft(ran.elapsed, 'the re-created lock is not taken down while its holder is live').toBeGreaterThanOrEqual(REPLACEMENT_GIVEN_BACK_AT_MS - 50);
  expect.soft(lockFailuresIn(dir), 'and no record').toEqual([]);
});

test('a capture leaves the ring recording on every outcome, and a ring a fault stopped is not the record of the next red (ring snapshot)', async ({}, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  // a ring of its own, so the fault made here does not stop the one the run records into
  const ring = testInfo.outputPath('ring');
  mkdirSync(ring, { recursive: true });
  const env = { CI: 'true', [OUT_VARIABLE]: ring };
  const started = await startKernel(env);
  expect(started.instance, JSON.stringify(started)).toBeTruthy();
  const on = async () => (await ringState(env)).on;
  try {
    const first = await keepKernel(testInfo.outputPath('first.txt.gz'), env);
    expect(first.file, JSON.stringify(first)).toBeTruthy();
    expect(await on(), 'a capture that was written').toBe('1');
    expect(first.reach, JSON.stringify(first.reach)).toMatchObject({ reaches: true });
    const lost = await keepKernel(join(ring, 'no-such-directory', 'x.txt.gz'), env);
    expect(lost.error, 'a capture that could not be written').toBeTruthy();
    expect(await on(), 'a capture that failed').toBe('1');
    expect(readdirSync(ring).filter((name) => /\.tmp$|^ring-lock$/.test(name)), 'a failed capture leaves no lock and no half segment').toEqual([]);
    // a second capture still holds the events of the first, whose swap emptied the live ring: the later file begins with the earlier segment
    const second = await keepKernel(testInfo.outputPath('second.txt.gz'), env);
    expect(second.segments, JSON.stringify(second)).toBeGreaterThanOrEqual(1);
    expect((await ringSeen(second.file, { early: /sched_/ })).early, 'an event of the first capture is in the second').not.toBeNull();
    // a ring a fault stopped (the spec's own, as evidence-real.spec.js stops a nested run's) ends before the next red: the file has content and is not evidence
    await pauseInstance(started.instance);
    await new Promise((resolve) => setTimeout(resolve, 1500));
    const stale = await keepKernel(testInfo.outputPath('stale.txt.gz'), env);
    expect(stale.file).toBeTruthy();
    expect(stale.reach.reaches, JSON.stringify(stale.reach)).toBe(false);
    expect(stale.reach.why).toMatch(/s before the red$|holds no event/);
    expect(await missingEvidence({ status: 'failed', expectedStatus: 'passed', flight: { kernel: stale, browserTrace: { file: 'x' } } }, env), 'the red-time rule names it').toEqual([expect.stringMatching(/^kernel ring \(does not reach the red/)]);
  } finally { await stopKernel(started, env); }
  expect(readdirSync(ring).filter((name) => name.startsWith('ring-segment-')), 'the segments go with the ring').toEqual([]);
});

test('four captures at once on one ring: each reads the snapshot it took and no other, and the lock is given back (the ring lock)', async ({}, testInfo) => {
  desktopOnly(testInfo);
  // a stand-in for the ring (a directory with the snapshot file that the swap writes and cat reads): the sequences are the real ones, so the race does not need a kernel to show.
  // The swap of a capture writes the snapshot buffer with the capture's own events; a second swap while a capture reads would show that capture another's events
  const directory = testInfo.outputPath('ring');
  const instance = testInfo.outputPath('instance');
  mkdirSync(directory, { recursive: true });
  mkdirSync(instance, { recursive: true });
  writeFileSync(join(instance, 'trace_clock'), '[mono] global\n');
  const module = pathToFileURL(join(import.meta.dirname, 'flight-tracefs.js')).href;
  const events = 4000;
  const code = `
    const { parentPort, workerData } = require('node:worker_threads');
    const { readFileSync, writeFileSync } = require('node:fs');
    const { gunzipSync } = require('node:zlib');
    import(workerData.module).then(async ({ snapshot }) => {
      const { instance, dir, holder, events } = workerData;
      let mixed = 0;
      let captures = 0;
      for (let round = 0; round < workerData.rounds; round += 1) {
        const tag = holder + '-' + round;
        // the swap puts this capture's events in the snapshot buffer, as the kernel's swap puts the live ring there
        const swap = () => {
          const lines = [];
          for (let i = 0; i < events; i += 1) lines.push('  ' + holder + '-1 [000] .... ' + round + '.' + String(i).padStart(6, '0') + ': sys_enter_futex: ' + tag);
          writeFileSync(instance + '/snapshot', '# tracer: nop\\n# entries-in-buffer/entries-written: ' + events + '/' + events + '   #P:4\\n#\\n' + lines.join('\\n') + '\\n');
          return { swapped: true };
        };
        const out = dir + '/' + tag + '.gz';
        const kept = await snapshot({ instance, out, dir, lines: events * 2, swap, clear: () => ({ cleared: true }) });
        captures += 1;
        // the last events of the file are this capture's: it read its own snapshot to the end
        const text = gunzipSync(readFileSync(out)).toString().split('\\n').filter((line) => line && !line.startsWith('#'));
        const own = text.slice(-events);
        if (kept.error || own.length !== events || own.some((line) => !line.endsWith(': sys_enter_futex: ' + tag))) mixed += 1;
      }
      parentPort.postMessage({ holder, mixed, captures });
    });`;
  const answers = await Promise.all(['a', 'b', 'c', 'd'].map((holder) => new Promise((resolve, reject) => {
    const worker = new Worker(code, { eval: true, workerData: { module, instance, dir: directory, holder, rounds: 6, events } });
    worker.on('message', resolve);
    worker.on('error', reject);
  })));
  expect(answers.map((each) => each.mixed), `captures that read another's events or none: ${JSON.stringify(answers)}`).toEqual([0, 0, 0, 0]);
  expect(readdirSync(directory), 'the lock is given back').not.toContain(LOCK_NAME);
  expect(readdirSync(directory).filter((name) => name.endsWith('.tmp')), 'no half segment').toEqual([]);
  expect(lockFailuresIn(directory), 'no capture went without the lock').toEqual([]);
  expect(segmentsIn(directory).at(-1).seq, 'one segment for each swap: 4 captures of 6 rounds, the newest kept').toBe(24);
});

test('a capture whose file cannot be written ends at once, with no reader of the ring left behind (a ring too large for the pipes, the sudo call that ran its whole limit)', async ({}, testInfo) => {
  desktopOnly(testInfo);
  // a stand-in for a ring that holds more than the pipes between cat, gzip and the file can carry (CI's quire-4296 hung its 'lost' capture for the 60 s limit of the root call)
  const instance = testInfo.outputPath('instance');
  mkdirSync(instance, { recursive: true });
  writeFileSync(join(instance, 'trace_clock'), '[mono] global\n');
  let state = 12345;
  const lines = [];
  for (let line = 0; line < 60000; line += 1) { state = (state * 1103515245 + 12345) % 2147483648; lines.push(`   node-1 [000] ..... ${line}.${state}: sys_futex(uaddr: ${state.toString(16)}${(state * 7).toString(16)})`); }
  writeFileSync(join(instance, 'snapshot'), `# entries-in-buffer/entries-written: 60000/60000   #P:4\n${lines.join('\n')}\n`);
  const ring = testInfo.outputPath('ring');
  mkdirSync(ring, { recursive: true });
  const args = JSON.stringify({ instance, out: join(ring, 'no-such-directory', 'x.txt.gz'), dir: ring });
  const began = Date.now();
  // as the recorder calls it (flight-recorder.js asRoot): the caller is done when the process has ended and every pipe it gave is closed, so a reader left alive holds the call.
  // The swap is the stand-in's (there is no kernel snapshot to swap): the snapshot file is as the swap left it
  const script = `import(${JSON.stringify(pathToFileURL(join(import.meta.dirname, 'flight-tracefs.js')).href)}).then(async ({ snapshot }) => { const answer = await snapshot({ ...JSON.parse(process.argv[1]), swap: () => ({ swapped: true }), clear: () => ({ cleared: true }) }); process.stdout.write(JSON.stringify(answer) + '\\n'); });`;
  const answer = await new Promise((resolve) => {
    execFile(process.execPath, ['-e', script, args], { timeout: 20000, killSignal: 'SIGKILL', encoding: 'utf8' }, (error, stdout) => resolve({ error, stdout, ms: Date.now() - began }));
  });
  const left = readdirSync('/proc').filter((name) => /^\d+$/.test(name)).filter((name) => { try { return readFileSync(`/proc/${name}/cmdline`, 'utf8').includes(instance); } catch (gone) { return false; } });
  for (const pid of left) { try { process.kill(Number(pid), 'SIGKILL'); } catch (gone) { /* it ended */ } }
  expect(answer.error, `the call ran to its limit (${answer.ms} ms): ${String(answer.stdout).slice(0, 300)}`).toBeNull();
  expect(JSON.parse(String(answer.stdout).trim().split('\n').pop()).error, 'the capture says why it has no file').toBeTruthy();
  expect(answer.ms, 'it ended at once').toBeLessThan(10000);
  expect(left, 'readers of the ring that outlived the capture').toEqual([]);
  expect(readdirSync(ring), 'no lock and no half segment is left').toEqual([]);
});

/** The widest silence of a kept ring after `since` (CLOCK_MONOTONIC seconds): { seconds, from }, read a line at a time. A pause of the ring is a silence of its length. */
async function widestSilence(file, since) {
  const reader = createInterface({ input: createReadStream(file).pipe(createGunzip()), crlfDelay: Infinity });
  let previous = null;
  let widest = { seconds: 0, from: null };
  for await (const line of reader) {
    const found = /^\s*.+-\d+\s+\[\d+\]\s+\S+\s+(\d+\.\d+):/.exec(line);
    if (!found || Number(found[1]) < since) continue;
    const at = Number(found[1]);
    if (previous !== null && at - previous > widest.seconds) widest = { seconds: at - previous, from: previous };
    previous = at;
  }
  return widest;
}

// The ticket's event (#910, run 40313494155): a capture of one worker held the ring paused for 13 s, a renderer in the other worker began its untimed
// wait in that window, and the ring never held the wait. The capture here is real (keepKernel, the root step and all) and cannot end: its file is a pipe
// that nobody reads, so it holds the ring lock and has taken its snapshot, and stays in the middle of reading the ring until the test reads the pipe.
test('a capture is reading the ring while a renderer in another page begins an untimed futex wait: the wait is in the ring (#910)', async ({ playwright, launchOptions }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  test.setTimeout(testInfo.timeout + CAPTURE_MOST_MS + 60000);
  const directory = process.env[OUT_VARIABLE];
  const pipe = testInfo.outputPath('capture.pipe');
  expect(spawnSync('mkfifo', [pipe]).status, 'mkfifo makes the pipe the capture writes to').toBe(0);
  const segmentsBegun = () => new Set(readdirSync(directory).filter((name) => /^ring-segment-\d+\.tmp$/.test(name)));
  const own = await playwright.chromium.launch(launchOptions);
  let hang = null;
  let reading = null;
  let draining = null;
  try {
    const page = await (await own.newContext()).newPage();
    const armed = await arm(page);
    const before = segmentsBegun();
    let capturing = true;
    reading = keepKernel(pipe, process.env).finally(() => { capturing = false; });
    // the capture has taken its snapshot when its segment is begun (flight-tracefs.js writes the segment's file right after the swap)
    await expect.poll(() => [...segmentsBegun()].some((name) => !before.has(name)), { timeout: 30000, message: 'the capture took its snapshot' }).toBe(true);
    const written = (await ringStats(process.env)).written;
    // the renderer begins its wait now, while the capture is in the middle of reading
    hang = await hangPage(page, { session: async () => armed.session });
    let waiting = null;
    await expect.poll(async () => {
      for (const renderer of (await processes(own)).filter((each) => each.type === 'renderer')) {
        const answer = await readSyscall(renderer.id);
        const call = /^202 (0x[0-9a-f]+) (0x[0-9a-f]+) (0x[0-9a-f]+) (0x[0-9a-f]+)/.exec(answer.syscall || '');
        if (call && (parseInt(call[2], 16) & 0x7f) === 9 && /^0x0+$/.test(call[4])) { waiting = { pid: renderer.id, address: call[1].slice(2), syscall: answer.syscall }; return true; }
      }
      return false;
    }, { timeout: 30000, message: 'a renderer is in an untimed futex wait' }).toBe(true);
    expect(capturing, 'the capture is still reading when the wait has begun (else this test shows nothing)').toBe(true);
    // the ring recorded all the while: events came in during the capture
    await new Promise((resolve) => setTimeout(resolve, 3000));
    const during = await ringStats(process.env);
    expect.soft(during.on, 'the ring records while a capture reads it').toBe('1');
    expect.soft(during.written, 'and takes events').toBeGreaterThan(written);
    // the capture ends: its pipe is read
    draining = (async () => { for await (const chunk of createReadStream(pipe)) { void chunk; } })();
    const first = await reading;
    await draining;
    expect(first.file, JSON.stringify(first)).toBeTruthy();
    // the next capture, whichever worker or watchdog makes it, has the wait: it began after the first one's snapshot, in the live ring
    const next = await keepKernel(testInfo.outputPath('after.txt.gz'), process.env);
    expect(next.file, JSON.stringify(next)).toBeTruthy();
    // no hole: from the first capture's snapshot to the end of the next one the ring has no silence of seconds (a ring paused for the capture has the length of the capture)
    const silence = await widestSilence(next.file, first.lastAt);
    expect.soft(silence.seconds, `the widest silence of the ring after the first capture's snapshot began at ${silence.from}`).toBeLessThan(1.5);
    const history = await futexAnalysis(next.file, { address: waiting.address, tid: waiting.pid });
    expect(history.waiter.lastWait, `the ring holds the renderer's wait (${waiting.syscall}): ${JSON.stringify(history.waiter)}`).not.toBeNull();
    expect(history.waiter.lastWait.untimed).toBe(true);
    expect(history.onAddress.events, 'and the address it waits on').toBeGreaterThan(0);
    expect(history.waiter.lastWait.at, 'the wait began after the capture took its snapshot').toBeGreaterThan(first.lastAt);
  } finally {
    if (hang) hang.release();
    if (!draining) { draining = (async () => { for await (const chunk of createReadStream(pipe)) { void chunk; } })(); }
    if (reading) await reading.catch(() => {});
    await draining.catch(() => {});
    await own.close().catch(() => {});
  }
});

test('the job-level check: a test that ended unexpectedly names a kernel ring or it is missing, a named error is repeated, no report is a failure', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const kept = testInfo.outputPath('flight-1-kernel.txt.gz');
  writeFileSync(kept, 'x');
  const reaching = testInfo.outputPath('flight-1-kernel.txt.gz.reach.json');
  writeFileSync(reaching, JSON.stringify({ redAt: 100, lastAt: 100.2, reaches: true }));
  const stale = testInfo.outputPath('stale.reach.json');
  writeFileSync(stale, JSON.stringify({ redAt: 100, lastAt: 40, reaches: false, why: 'the last event is 60.0 s before the red' }));
  const report = (status, message, attachments = []) => ({ suites: [{ specs: [{ title: 'a test', file: 'a.spec.js', tests: [{ expectedStatus: 'passed', results: [{ status, errors: message ? [{ message }] : [], attachments }] }] }] }] });
  expect(missingFields([report('failed', 'Error: EVIDENCE MISSING: kernel ring (not written)\n at x')])).toEqual(expect.arrayContaining(['kernel ring (not written) (test: a test)']));
  expect(missingFields([report('failed', 'Error: expected 1 to be 2')])[0], 'a plain failure with no record').toMatch(/^kernel ring \(test "a test" ended failed and left no record/);
  expect(missingFields([report('timedOut', 'Test timeout of 90000ms exceeded')])[0]).toMatch(/ended timedOut and left no record/);
  expect(missingFields([report('failed', 'x', [{ name: 'flight-kernel', path: kept }, { name: 'flight-kernel-reach', path: reaching }])]), 'a record named in the report').toEqual([]);
  expect(missingFields([report('failed', 'x', [{ name: 'flight-kernel', path: kept }, { name: 'flight-kernel-reach', path: stale }])])[0], 'a ring that ends before the red (a ring a fault stopped) is not a record of it').toMatch(/does not reach the red: the last event is 60.0 s before the red/);
  expect(missingFields([report('failed', 'x', [{ name: 'flight-kernel', path: kept }])])[0], 'a ring with no reach record').toMatch(/has no reach record/);
  expect(missingFields([report('failed', 'x', [{ name: 'flight-kernel', path: testInfo.outputPath('gone.gz') }])])[0], 'a record named but gone').toMatch(/left no record/);
  expect(missingFields([report('failed', 'x')], [{ source: 'the runner', file: kept, test: 'file > a test', reach: { reaches: true } }]), 'a record the runner wrote').toEqual([]);
  expect(missingFields([report('failed', 'x')], [{ source: 'the runner', file: kept, test: 'file > a test', reach: { reaches: false, why: 'stale' } }])[0], 'a record the runner wrote that stops before the red').toMatch(/does not reach the red: stale/);
  expect(missingFields([report('passed')])).toEqual([]);
  expect(missingFields([])).toEqual([]);
  expect(missingFields([], [], { requireReport: true })[0]).toMatch(/^report \(no Playwright JSON report/);
  expect(missingFields([{ errors: [{ message: 'Error: PREFLIGHT FAILED: watchdog: exited at start' }], suites: [] }])[0]).toMatch(/^watchdog: exited at start/);
  expect(missingFields([report('passed')], [], { fatal: ['watchdog: no heartbeat for 9000 ms'] })).toEqual(['watchdog: no heartbeat for 9000 ms']);
});

test('what a system call that waits for ever looks like: the table reads epoll, poll, ppoll and read, and tells a timeout from none', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const line = (nr, args) => `${nr} ${args.map((each) => `0x${each.toString(16)}`).join(' ')} 0x7ffd1000 0x7f0010`;
  const minusOne = 0xffffffffffffffffn;
  expect(parseBlocked(line(232, [3, 0x7ffd, 32, minusOne, 0, 0]))).toMatchObject({ name: 'epoll_wait', untimed: true, fd: 3 });
  expect(parseBlocked(line(232, [3, 0x7ffd, 32, 100, 0, 0]))).toMatchObject({ name: 'epoll_wait', untimed: false });
  expect(parseBlocked(line(281, [3, 0x7ffd, 32, 0xffffffff, 0, 0]))).toMatchObject({ name: 'epoll_pwait', untimed: true });
  expect(parseBlocked(line(7, [0x7ffd, 2, minusOne, 0, 0, 0]))).toMatchObject({ name: 'poll', untimed: true });
  expect(parseBlocked(line(7, [0x7ffd, 2, 1000, 0, 0, 0]))).toMatchObject({ name: 'poll', untimed: false });
  expect(parseBlocked(line(271, [0x7ffd, 2, 0, 0, 0, 0]))).toMatchObject({ name: 'ppoll', untimed: true });
  expect(parseBlocked(line(271, [0x7ffd, 2, 0x7ffe, 0, 0, 0]))).toMatchObject({ name: 'ppoll', untimed: false });
  expect(parseBlocked(line(0, [5, 0x7ffd, 4096, 0, 0, 0]))).toMatchObject({ name: 'read', untimed: true, fd: 5 });
  expect(parseBlocked(line(1, [6, 0x7ffd, 4096, 0, 0, 0]))).toMatchObject({ name: 'write', fd: 6 });
  expect(parseBlocked(line(202, [0x7ffc, 0x189, 0, 0, 0, 0xffffffff]))).toMatchObject({ name: 'futex', untimed: true });
  expect(parseBlocked(line(202, [0x7ffc, 0x89, 0, 0x7ffd, 0, 0xffffffff]))).toMatchObject({ name: 'futex', untimed: false });
  expect(parseBlocked(line(35, [0x7ffd, 0, 0, 0, 0, 0])), 'a sleep with a time is not a wait for ever').toBeNull();
  expect(parseBlocked('running')).toBeNull();
  expect(parseBlocked('-1 0x7ffd1000 0x7f0010')).toBeNull();
});

test('a main thread blocked in a call that is not a futex (a read on a pipe, a write to a full pipe): the watchdog names the call, the file and the other end', async ({}, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  const out = testInfo.outputPath('blocked');
  // `cat` waits in read(0) on a pipe whose write end this process holds; `yes` in write(1) to a pipe nobody reads
  // real pipes (a named pipe is one, and node's own stdio pipes are socket pairs): this process holds each one open for reading and writing
  mkdirSync(out, { recursive: true });
  const emptyPipe = join(out, 'empty.fifo');
  const fullPipe = join(out, 'full.fifo');
  for (const fifo of [emptyPipe, fullPipe]) expect(spawnSync('mkfifo', [fifo]).status).toBe(0);
  const emptyHeld = openSync(emptyPipe, 'r+');
  const fullHeld = openSync(fullPipe, 'r+');
  const reader = spawn('cat', [], { stdio: [emptyHeld, 'ignore', 'ignore'] });
  const writer = spawn('yes', [], { stdio: ['ignore', fullHeld, 'ignore'] });
  const watchdog = startWatchdog(process.env[INSTANCE_VARIABLE], process.env, out, 3000, '^(cat|yes)$');
  try {
    const reports = () => (existsSync(out) ? readdirSync(out).filter((name) => /^watchdog-\d+-\d+-\d+\.json$/.test(name)).flatMap((name) => { try { return [JSON.parse(readFileSync(join(out, name), 'utf8'))]; } catch (partial) { return []; } }) : []);
    await expect.poll(() => reports().map((each) => each.blocked.name).sort(), { timeout: 60000 }).toEqual(['read', 'write']);
    for (const report of reports()) {
      expect(report.blocked.untimed).toBe(true);
      // a named pipe is told by its path, an anonymous one by pipe:[inode]
      expect(report.target, `${report.blocked.name} waits on a pipe`).toMatch(report.blocked.name === 'read' ? /empty\.fifo$/ : /full\.fifo$/);
      expect(report.peers.map((peer) => peer.pid), 'the other end of the pipe is held by this process').toContain(process.pid);
      expect(report.reason).toMatch(/untimed wait \((read|write)\)/);
      expect(report.threads.length).toBeGreaterThan(0);
    }
  } finally { reader.kill('SIGKILL'); writer.kill('SIGKILL'); stopWatchdog(watchdog); closeSync(emptyHeld); closeSync(fullHeld); }
});

/** Runs a command as root (through sudo where this is not root). */
const asRootCommand = (command, args, input) => spawnSync(isRootUser ? command : 'sudo', isRootUser ? args : ['-n', command, ...args], { encoding: 'utf8', input });
const isRootUser = typeof process.getuid === 'function' && process.getuid() === 0;

test('a renderer killed by the kernel for want of memory: the OOM killer\'s choice is in the ring and its line in the kernel log of the crash capture', async ({ browser, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  test.setTimeout(testInfo.timeout + 120000);
  const unified = existsSync('/sys/fs/cgroup/cgroup.controllers');
  const base = unified ? '/sys/fs/cgroup' : '/sys/fs/cgroup/memory';
  const group = `${base}/quire-oom-${process.pid}`;
  const context = await browser.newContext();
  const hog = await context.newPage();
  await hog.setContent('<p>about to run out of memory</p>');
  const renderers = (await processes(browser)).filter((each) => each.type === 'renderer').map((each) => each.id);
  const victim = renderers.find((pid) => /RendererMain|renderer/.test(readFileSync(`/proc/${pid}/cmdline`, 'utf8')) && existsSync(`/proc/${pid}`));
  try {
    if (unified) asRootCommand('tee', [`${base}/cgroup.subtree_control`], '+memory');
    expect(asRootCommand('mkdir', [group]).status, 'a cgroup for the renderer').toBe(0);
    const resident = Number((/VmRSS:\s+(\d+) kB/.exec(readFileSync(`/proc/${victim}/status`, 'utf8')) || [0, 100000])[1]) * 1024;
    const limit = String(resident + 150 * 1024 * 1024);
    expect(asRootCommand('tee', [`${group}/${unified ? 'memory.max' : 'memory.limit_in_bytes'}`], limit).status).toBe(0);
    if (unified) asRootCommand('tee', [`${group}/memory.swap.max`], '0');
    expect(asRootCommand('tee', [`${group}/cgroup.procs`], String(victim)).status, 'the renderer joins it').toBe(0);
    hog.evaluate(() => { const held = []; for (let i = 0; i < 60; i += 1) held.push(new Uint8Array(20e6).fill(1)); return held.length; }).catch(() => {});
    await expect.poll(() => stallWatch.state.flight, { timeout: 90000 }).toBeTruthy();
    await expect.poll(() => readdirSync(testInfo.outputDir).some((name) => /^crash-\d+\.json$/.test(name)), { timeout: 60000 }).toBe(true);
    const seenOom = await ringHas(stallWatch.state.flight.kernel.file, { marked: new RegExp(`mark_victim.*pid=${victim}`), killed: new RegExp(`signal_generate: sig=9 .*pid=${victim} `) });
    expect(seenOom.marked, 'the OOM killer marked the renderer').not.toBeNull();
    expect(seenOom.killed, 'and the kill is in the ring').not.toBeNull();
    const body = JSON.parse(readFileSync(join(testInfo.outputDir, readdirSync(testInfo.outputDir).find((name) => /^crash-\d+\.json$/.test(name))), 'utf8'));
    expect(JSON.stringify(body.kernelLog), 'dmesg says it').toMatch(/Killed process|out of memory/i);
  } finally {
    await context.close().catch(() => {});
    asRootCommand('rmdir', [group]);
  }
});

test('a jump of the wall clock: the watchdog keeps the jump, against the monotonic clock the ring and the trace use', async ({}, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  const set = (milliseconds) => asRootCommand('date', ['-s', `@${(milliseconds / 1000).toFixed(3)}`]);
  const wall = Date.now();
  const mono = performance.now();
  expect(set(wall + 700).status, 'the clock can be set').toBe(0);
  await new Promise((resolve) => setTimeout(resolve, 400));
  expect(set(wall + (performance.now() - mono)).status).toBe(0);
  const out = process.env[OUT_VARIABLE];
  const jumps = () => readdirSync(out).filter((name) => /^clock-jumps-/.test(name)).flatMap((name) => JSON.parse(readFileSync(join(out, name), 'utf8')));
  await expect.poll(() => { const seen = jumps().map((each) => each.jumpMs); return seen.some((jump) => jump > 400 && jump < 1000) && seen.some((jump) => jump < -400 && jump > -1000); }, { timeout: 20000 }).toBe(true);
  // and the unit: a wall clock that moves 5 s while the monotonic one moves 100 ms
  const dog = new Watchdog({ root: process.pid, out: testInfo.outputPath('jumps') });
  dog.tick(0, 1000);
  dog.tick(100, 6100);
  expect(dog.clockJumps).toHaveLength(1);
  expect(dog.clockJumps[0].jumpMs).toBe(5000);
});

test('a network stall (a fetch to a server that never answers, the page free): the request is in the capture and in Chrome\'s trace, with its age', async ({ page, browser }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  test.setTimeout(testInfo.timeout + CAPTURE_MOST_MS);
  const held = new Set();
  // the page itself is answered; the one request under test never is
  const server = createServer((request, response) => { if (request.url === '/') { response.setHeader('content-type', 'text/html'); response.end('<p>waiting</p>'); } });
  server.on('connection', (socket) => held.add(socket));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const url = `http://127.0.0.1:${server.address().port}/never-answered`;
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    const armed = await arm(page);
    await page.evaluate((target) => { fetch(target, { mode: 'no-cors' }).catch(() => {}); }, url);
    await new Promise((resolve) => setTimeout(resolve, 2500));
    const found = await capture(page, armed, 'induced: a fetch nobody answers', browser);
    expect(found.answers.task.answered, 'the page is free').toBe(true);
    expect(found.history.inFlight.some((each) => each.url === url && each.ageMs >= 2000)).toBe(true);
    const kept = await keepBoth(browser, (name) => testInfo.outputPath(`net-${name}`), process.env, true);
    expect(kept.browserTrace.pendingRequests.some((each) => each.url === url && each.ageMs >= 2000), JSON.stringify(kept.browserTrace.pendingRequests)).toBe(true);
  } finally {
    // the request in flight ends with the page's document, before the server's sockets go
    await page.goto('about:blank').catch(() => {});
    for (const socket of held) socket.destroy();
    server.close();
  }
});

test('a page that is slow, not frozen (quire#600): the long task, the page\'s attempts and the runner\'s load are in the capture, and the task is in Chrome\'s trace', async ({ page, browser, stallWatch }, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  test.setTimeout(testInfo.timeout + CAPTURE_MOST_MS);
  await page.setContent('<button id="go">go</button>');
  const armed = await arm(page);
  // 1.5 s of script on the main thread, as a heavy layout is
  await page.evaluate(() => new Promise((resolve) => setTimeout(() => { const start = performance.now(); while (performance.now() - start < 1500) { /* a long task */ } resolve(1); }, 0)));
  await new Promise((resolve) => setTimeout(resolve, 1200));
  const found = await capture(page, armed, 'induced: a slow page', browser);
  expect(found.answers.task.answered).toBe(true);
  // the page's tasks are taken by whichever session harvests first (the test's own, here, and the watch's probe every 2 s): between them they hold the task
  expect(Array.isArray(found.pageTiming.longTasks) && Array.isArray(found.pageTiming.attempts), 'the capture has the fields').toBe(true);
  const watched = await stallWatch.evidence();
  const tasks = [...found.pageTiming.longTasks, ...watched.pageTiming.flatMap((each) => each.longTasks)];
  expect(tasks.some((each) => each.ms >= 1000), JSON.stringify(tasks).slice(0, 300)).toBe(true);
  expect(found.runnerLoad.summary.reading, 'the runner\'s load over the last minute').toMatch(/CPU pressure/);
  const kept = await keepBoth(browser, (name) => testInfo.outputPath(`slow-${name}`), process.env, true);
  const trace = JSON.parse(gunzipSync(readFileSync(kept.browserTrace.file)).toString());
  expect((trace.traceEvents || trace).some((event) => event.dur >= 1000000 && /FunctionCall|EvaluateScript|RunTask|TimerFire/.test(event.name)), 'a task of a second or more in Chrome\'s trace').toBe(true);
});

test('a banner or a toast over a control (quire#556): what is on the page, with the box of each overlay, and what Playwright says intercepted the click', async ({ page }, testInfo) => {
  desktopOnly(testInfo);
  await page.setContent('<style>.banner { position: fixed; top: 0; left: 0; width: 300px; height: 60px; background: #fdd; z-index: 5 } #menu { position: absolute; top: 10px; left: 10px }</style><div class="banner" role="alert" id="error-banner">Could not read the chapter</div><button id="menu">More options</button>');
  const clicked = await page.click('#menu', { timeout: 1500 }).then(() => 'clicked', (error) => String(error.message));
  expect(clicked).toMatch(/intercepts pointer events/);
  expect(clicked).toMatch(/error-banner/);
  const state = await pageState(page);
  const banner = state.overlays.find((each) => each.element.includes('error-banner'));
  expect(banner.box).toEqual([0, 0, 300, 60]);
  expect(banner.text).toBe('Could not read the chapter');
  expect(state.alerts[0]).toContain('Could not read the chapter');
});

test('two screens that differ by a pixel (quire#546): where it is, both colours and the elements there', async ({ page }, testInfo) => {
  desktopOnly(testInfo);
  await page.setContent('<style>body { margin: 0; background: #fff } #dot { position: absolute; left: 300px; top: 200px; width: 1px; height: 1px; background: #000; display: none }</style><div id="dot"></div>');
  const before = { screen: await page.screenshot({ animations: 'disabled' }) };
  await page.evaluate(() => { document.getElementById('dot').style.display = 'block'; });
  const after = { screen: await page.screenshot({ animations: 'disabled' }) };
  const found = await pixelDiff(page, before, after);
  expect(found.count).toBe(1);
  expect(found.list[0]).toMatchObject({ x: 300, y: 200, before: [255, 255, 255], after: [0, 0, 0] });
  expect(found.dom[0].stack.join(' ')).toContain('div#dot');
});

test('what the recorder costs: the job\'s own measurement of a loop of page cycles with the rings on against off, made before the first test, and the numbers in the log', async ({}, testInfo) => {
  desktopOnly(testInfo);
  await recorderOn();
  // The measurement needs the kernel ring off, which only the preflight can do: it pauses the ring before any worker records, and no capture ever
  // stops the ring (ring snapshot). This test reads what it wrote and holds the ratio.
  const file = join(process.env[OUT_VARIABLE], COST_FILE);
  expect(existsSync(file), `${file} is written by the preflight's measurement (QUIRE_NO_COST skips it)`).toBe(true);
  const measured = JSON.parse(readFileSync(file, 'utf8'));
  console.error(`[cost] ${measured.cycles} page cycles: x${measured.ratio.toFixed(2)} with both rings on against off; rounds off ${measured.off.map(Math.round)}, on ${measured.on.map(Math.round)}`);
  expect(measured.ratio, 'both rings together stay under 75% extra on a loop of nothing but IPC').toBeLessThan(1.75);
});

test('what the runner can do that bears on the classes the record cannot see is read each run and a change is a notice', async ({}, testInfo) => {
  desktopOnly(testInfo);
  const no = async () => ({ ok: false, stdout: '', stderr: 'No supported events found.' });
  const yes = async () => ({ ok: true, stdout: ' 1,000 cycles', stderr: '' });
  const unchanged = await capabilities({ run: no, fetchHead: async () => 404, version: '149.0.7827.55' });
  expect(unchanged.counters.available).toBe(false);
  expect(unchanged.notice).toEqual([]);
  expect(unchanged.symbols.map((each) => each.status)).toEqual([404, 404, 404]);
  expect(unchanged.rr, 'rr is not installed: said so').toMatchObject({ installed: false, record: { works: false } });
  const changed = await capabilities({ run: yes, fetchHead: async (url) => (url.endsWith('symbols.zip') ? 200 : 404), version: '149.0.7827.55' });
  expect(changed.notice.join('\n')).toMatch(/rr may now work/);
  expect(changed.notice.join('\n')).toMatch(/a symbol file now exists/);
  expect(changed.notice.join('\n')).toMatch(/rr record works on this runner/);
  // rr is asked itself: installed, and refusing on the CPU as it did on the runner (2026-10-20), is read and written down without a notice
  const asked = [];
  const refusing = async (command, args, env) => {
    asked.push([command, ...args, env && env._RR_TRACE_DIR]);
    if (command === 'rr' && args[0] === 'record') return { ok: false, stdout: '', stderr: 'rr: Unhandled CPU model: Intel CPU type 0xc06f0 unknown' };
    if (command === 'rr') return { ok: true, stdout: 'rr version 5.7.0\n', stderr: '' };
    return { ok: false, stdout: '', stderr: 'No supported events found.' };
  };
  const refused = await capabilities({ run: refusing, fetchHead: async () => 404, version: '149.0.7827.55', traceDirectory: '/trace-here' });
  expect(refused.rr).toMatchObject({ installed: true, version: 'rr version 5.7.0', record: { works: false } });
  expect(refused.rr.record.text).toMatch(/Intel CPU type 0xc06f0 unknown/);
  expect(refused.notice).toEqual([]);
  expect(asked, 'rr is run, and records into the directory it was given').toContainEqual(['rr', 'record', 'true', '/trace-here']);
  // and this run's own reading, written by the preflight
  const written = process.env[OUT_VARIABLE] && join(process.env[OUT_VARIABLE], 'capabilities.json');
  expect(written && existsSync(written), 'the preflight wrote capabilities.json').toBe(true);
  const reading = JSON.parse(readFileSync(written, 'utf8'));
  console.error(`[capabilities] perf cycles available: ${reading.counters.available}; rr: ${JSON.stringify(reading.rr)}; symbols: ${JSON.stringify(reading.symbols)}`);
  expect(reading.counters).toHaveProperty('available');
  expect(reading.rr, 'the preflight asked rr itself').toHaveProperty('installed');
  expect(reading.rr.record, 'and said what its recording did').toHaveProperty('works');
});
