// The #293 UX review's screenshots: the e2e suite's fixtures and helpers,
// one run per viewport (and theme, through THEME=light|dark)
import { defineConfig } from '@playwright/test';

const args = ['--no-sandbox', '--disable-setuid-sandbox', '--disable-gpu', '--disable-dev-shm-usage', '--disable-software-rasterizer'];
const base = { browserName: 'chromium', launchOptions: { args } };

export default defineConfig({
  testDir: '.',
  timeout: 300000,
  workers: 1,
  expect: { timeout: 15000 },
  use: { baseURL: 'http://localhost:3748', headless: true, screenshot: 'off', trace: 'off' },
  webServer: { command: 'npx serve dist/pwa -l 3748 --no-clipboard', cwd: '..', port: 3748, reuseExistingServer: true },
  projects: [
    // the app, as the Android app runs it (the e2e suite's android project)
    { name: 'android', use: { ...base, viewport: { width: 412, height: 915 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true,
      userAgent: 'Mozilla/5.0 (Linux; Android 15; Pixel 8 Build/AP4A.250105.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/140.0.7339.207 Mobile Safari/537.36' } },
    { name: 'narrow', use: { ...base, viewport: { width: 320, height: 640 } } },
    { name: 'desktop', use: { ...base, viewport: { width: 1024, height: 768 } } },
  ],
});
