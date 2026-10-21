// The config of the real-path tests of the evidence (evidence-real.spec.js, #575): a Playwright run of its own, started by a test,
// with the suite's global setup (the preflight), fixtures (the stall watch) and the runner's evidence reporter, on small cases.
// What each case does and what the run is given by the environment is the spec's. Keyword: nested run.
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  testMatch: /\.case\.js$/,
  // in the run's own directory (its working directory): runs side by side must not clear each other's results
  outputDir: `${process.cwd()}/test-results/nested`,
  globalSetup: '../global-setup.js',
  timeout: Number(process.env.QUIRE_NESTED_TIMEOUT || 15000),
  workers: 1,
  retries: 0,
  reporter: [['list'], ['json'], ['../evidence-reporter.js']],
  use: {
    headless: true,
    launchOptions: {
      args: ['--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage', '--disable-software-rasterizer'],
      env: { ...process.env, FC_FONTATIONS: '1' },
      ...(process.env.QUIRE_NESTED_EXECUTABLE ? { executablePath: process.env.QUIRE_NESTED_EXECUTABLE } : {}),
    },
  },
  projects: [{ name: 'nested', use: { browserName: 'chromium' } }],
});
