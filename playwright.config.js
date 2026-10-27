import { defineConfig } from '@playwright/test';

const chromiumArgs = [
  '--no-sandbox',
  '--disable-setuid-sandbox',
  '--disable-gpu',
  '--disable-dev-shm-usage',
  '--disable-software-rasterizer',
];

// The browser's environment. Chromium 145's browser process calls
// setenv("FC_FONTATIONS", "1") on a thread-pool thread about 50 ms after it
// starts. When the variable is not there, glibc grows `environ`: it
// reallocates the array and frees the old one, while the D-Bus thread (and
// the resolver, and tzset) may be in getenv() scanning that very array, and
// the freed array then reads as allocator garbage: SEGV_MAPERR in getenv,
// the browser dead at launch (quire#599: three launches in 3,600 e2e jobs).
// With the variable already set to the value Chromium sets, setenv replaces
// one pointer in place and the array is never freed. The value is the one
// Chromium writes itself, so the browser does the same as before.
// The sanitizer step of check.yml (quire#575) runs an AddressSanitizer build of Chromium: its path, and where its reports go
const chromiumEnv = { ...process.env, FC_FONTATIONS: '1', ...(process.env.QUIRE_SANITIZER_LOGS ? { ASAN_OPTIONS: `log_path=${process.env.QUIRE_SANITIZER_LOGS}/asan:detect_leaks=0:symbolize=1` } : {}) };
const chromiumLaunch = { args: chromiumArgs, env: chromiumEnv, ...(process.env.QUIRE_BROWSER_EXECUTABLE ? { executablePath: process.env.QUIRE_BROWSER_EXECUTABLE } : {}) };

// Android's System WebView on a Pixel, as the app's pages see it
const ANDROID_USER_AGENT = 'Mozilla/5.0 (Linux; Android 15; Pixel 8 Build/AP4A.250105.002; wv) '
  + 'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/140.0.7339.207 Mobile Safari/537.36';

// Where the app is served. `gen-pwa test` (pwa's test_run, pwa#82, #499)
// serves dist/pwa itself on 127.0.0.1, at a port the kernel picks
// (PWA_TEST_BASE_URL, PWA_TEST_PORT); a bare `npx playwright test` serves
// it here, at QUIRE_PORT, so two runs of the suite from two checkouts do
// not share (and serve each other's) build. Either way the page is at
// localhost, the host the specs that keep every other host away let
// through
const served = process.env.PWA_TEST_BASE_URL && process.env.PWA_TEST_PORT;
const port = Number(process.env.PWA_TEST_PORT || process.env.QUIRE_PORT || 3748);

// `gen-pwa test` runs the suite twice, the @serial tests alone on one
// worker and then the others; with --timings each run's JSON report is
// named for it (serial.json, parallel.json, run.json). Playwright clears
// its output directory as a run starts, so each run keeps its outputs (the
// screenshots, traces and stall captures, and the HTML report) under its
// own name, or the second run would delete the first's
const run = (process.env.PLAYWRIGHT_JSON_OUTPUT_NAME || '').match(/(?:^|[\\/])(serial|parallel|run)\.json$/)?.[1];
if (run && !process.env.PLAYWRIGHT_HTML_OUTPUT_DIR) process.env.PLAYWRIGHT_HTML_OUTPUT_DIR = `playwright-report/${run}`;

export default defineConfig({
  testDir: './e2e',
  // every spec's test carries the stall watch (e2e/stall-capture.js, #244)
  globalSetup: './e2e/global-setup.js',
  outputDir: run ? `test-results/${run}` : 'test-results',
  timeout: 90000,
  expect: { timeout: 15000 },
  use: {
    baseURL: `http://localhost:${port}`,
    screenshot: 'on',
    trace: 'on',
    headless: true,
  },
  webServer: served ? undefined : {
    command: `npx serve dist/pwa -l ${port} --no-clipboard`,
    port,
    reuseExistingServer: !process.env.CI,
  },
  projects: [
    {
      name: 'desktop',
      use: {
        browserName: 'chromium',
        viewport: { width: 1024, height: 768 },
        launchOptions: chromiumLaunch,
      },
    },
    {
      name: 'mobile-portrait',
      use: {
        browserName: 'chromium',
        viewport: { width: 375, height: 667 },
        launchOptions: chromiumLaunch,
      },
    },
    // the narrowest width content must work at (WCAG 1.4.10 Reflow:
    // 320 CSS px), which a phone reaches at a large display size (#265)
    // (the window's projects run the layout's specs, and the relaunch
    // specs, which hold in every project: #302)
    {
      name: 'narrow',
      testMatch: /(layout|library-grouping|smoke|page-turn|icons|relaunch|relaunch-sync)\.spec\.js/,
      use: {
        browserName: 'chromium',
        viewport: { width: 320, height: 640 },
        launchOptions: chromiumLaunch,
      },
    },
    // Android, as the app runs there (#295): a Pixel-class phone (412 x
    // 915 CSS px at 2.625 device pixels a CSS px, a touch screen, the
    // WebView's user agent), its status bar and gesture navigation
    // given as the safe area's insets (fixtures.js), and the app's
    // Android branch where it keys on the platform. Every spec runs
    // here, never narrowed (scripts/ci-groups.py fails CI if it is); a
    // spec that cannot apply on Android skips itself, saying why
    {
      name: 'android',
      use: {
        browserName: 'chromium',
        viewport: { width: 412, height: 915 },
        deviceScaleFactor: 2.625,
        isMobile: true,
        hasTouch: true,
        userAgent: ANDROID_USER_AGENT,
        launchOptions: chromiumLaunch,
      },
    },
    {
      name: 'mobile-landscape',
      testMatch: /(layout|library-grouping|smoke|page-turn|relaunch|relaunch-sync)\.spec\.js/,
      use: {
        browserName: 'chromium',
        viewport: { width: 667, height: 375 },
        launchOptions: chromiumLaunch,
      },
    },
    {
      name: 'tablet',
      testMatch: /(layout|library-grouping|smoke|page-turn|relaunch|relaunch-sync)\.spec\.js/,
      use: {
        browserName: 'chromium',
        viewport: { width: 768, height: 1024 },
        launchOptions: chromiumLaunch,
      },
    },
    {
      name: 'wide',
      testMatch: /(layout|library-grouping|smoke|page-turn|relaunch|relaunch-sync)\.spec\.js/,
      use: {
        browserName: 'chromium',
        viewport: { width: 1440, height: 900 },
        launchOptions: chromiumLaunch,
      },
    },
  ],
});
