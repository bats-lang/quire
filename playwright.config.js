import { defineConfig } from '@playwright/test';

const chromiumArgs = [
  '--no-sandbox',
  '--disable-setuid-sandbox',
  '--disable-gpu',
  '--disable-dev-shm-usage',
  '--disable-software-rasterizer',
];

export default defineConfig({
  testDir: './e2e',
  timeout: 90000,
  expect: { timeout: 15000 },
  use: {
    baseURL: 'http://localhost:3748',
    screenshot: 'on',
    trace: 'on',
    headless: true,
  },
  webServer: {
    command: 'npx serve dist/pwa -l 3748 --no-clipboard',
    port: 3748,
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
    {
      name: 'mobile-landscape',
      testMatch: /(layout|smoke|page-turn)\.spec\.js/,
      use: {
        browserName: 'chromium',
        viewport: { width: 667, height: 375 },
        launchOptions: { args: chromiumArgs },
      },
    },
    {
      name: 'tablet',
      testMatch: /(layout|smoke|page-turn)\.spec\.js/,
      use: {
        browserName: 'chromium',
        viewport: { width: 768, height: 1024 },
        launchOptions: { args: chromiumArgs },
      },
    },
    {
      name: 'wide',
      testMatch: /(layout|smoke|page-turn)\.spec\.js/,
      use: {
        browserName: 'chromium',
        viewport: { width: 1440, height: 900 },
        launchOptions: { args: chromiumArgs },
      },
    },
  ],
});
