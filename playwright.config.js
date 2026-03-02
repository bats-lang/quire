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
    baseURL: 'http://localhost:3737',
    screenshot: 'on',
    trace: 'on',
    headless: true,
  },
  webServer: {
    command: 'npx serve . -l 3737 --no-clipboard',
    port: 3737,
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
      use: {
        browserName: 'chromium',
        viewport: { width: 667, height: 375 },
        launchOptions: { args: chromiumArgs },
      },
    },
    {
      name: 'tablet',
      use: {
        browserName: 'chromium',
        viewport: { width: 768, height: 1024 },
        launchOptions: { args: chromiumArgs },
      },
    },
    {
      name: 'wide',
      use: {
        browserName: 'chromium',
        viewport: { width: 1440, height: 900 },
        launchOptions: { args: chromiumArgs },
      },
    },
  ],
});
