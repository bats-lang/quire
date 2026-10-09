import { defineConfig } from '@playwright/test';

const chromiumArgs = [
  '--no-sandbox',
  '--disable-setuid-sandbox',
  '--disable-gpu',
  '--disable-dev-shm-usage',
  '--disable-software-rasterizer',
];

// Android's System WebView on a Pixel, as the app's pages see it
const ANDROID_USER_AGENT = 'Mozilla/5.0 (Linux; Android 15; Pixel 8 Build/AP4A.250105.002; wv) '
  + 'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/140.0.7339.207 Mobile Safari/537.36';

// QUIRE_PORT: the port the app is served on, so two runs of the suite from two
// checkouts do not share (and serve each other's) build
const port = Number(process.env.QUIRE_PORT || 3748);

export default defineConfig({
  testDir: './e2e',
  // every spec's test carries the stall watch (e2e/stall-capture.js, #244)
  globalSetup: './e2e/global-setup.js',
  timeout: 90000,
  expect: { timeout: 15000 },
  use: {
    baseURL: `http://localhost:${port}`,
    screenshot: 'on',
    trace: 'on',
    headless: true,
  },
  webServer: {
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
        launchOptions: { args: chromiumArgs },
      },
    },
    {
      name: 'mobile-portrait',
      use: {
        browserName: 'chromium',
        viewport: { width: 375, height: 667 },
        launchOptions: { args: chromiumArgs },
      },
    },
    // the narrowest width content must work at (WCAG 1.4.10 Reflow:
    // 320 CSS px), which a phone reaches at a large display size (#265)
    // (the window's projects run the layout's specs, and the relaunch
    // specs, which hold in every project: #302)
    {
      name: 'narrow',
      testMatch: /(layout|smoke|page-turn|icons|relaunch|relaunch-sync)\.spec\.js/,
      use: {
        browserName: 'chromium',
        viewport: { width: 320, height: 640 },
        launchOptions: { args: chromiumArgs },
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
        launchOptions: { args: chromiumArgs },
      },
    },
    {
      name: 'mobile-landscape',
      testMatch: /(layout|smoke|page-turn|relaunch|relaunch-sync)\.spec\.js/,
      use: {
        browserName: 'chromium',
        viewport: { width: 667, height: 375 },
        launchOptions: { args: chromiumArgs },
      },
    },
    {
      name: 'tablet',
      testMatch: /(layout|smoke|page-turn|relaunch|relaunch-sync)\.spec\.js/,
      use: {
        browserName: 'chromium',
        viewport: { width: 768, height: 1024 },
        launchOptions: { args: chromiumArgs },
      },
    },
    {
      name: 'wide',
      testMatch: /(layout|smoke|page-turn|relaunch|relaunch-sync)\.spec\.js/,
      use: {
        browserName: 'chromium',
        viewport: { width: 1440, height: 900 },
        launchOptions: { args: chromiumArgs },
      },
    },
  ],
});
