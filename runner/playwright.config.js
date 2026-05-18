// @ts-check
const { defineConfig, devices } = require('@playwright/test');

/**
 * Playwright config for k8s-test-runner.
 *
 * Key choices for this project:
 * - testIdAttribute: 'data-test' — saucedemo uses data-test (not the default
 *   data-testid). Setting this lets us write `getByTestId('username')` cleanly.
 * - PLAYWRIGHT_OUTPUT_DIR env var: in the container, it's /test-output/playwright
 *   (a writable directory owned by pwuser). Locally, it falls back to ./test-results.
 * - JSON reporter: emits a structured results file we'll upload to S3 in Week 3.
 * - List reporter: human-readable output in stdout (visible via `kubectl logs`).
 * - workers: 1 inside each container. Parallelism comes from K8s Jobs running
 *   N pods in parallel, NOT from Playwright's internal worker pool.
 * - retries: 1. Containerized parallel runs should fail fast, not paper over flakiness.
 * - timeout: 30s per test. Sauce demo is fast; longer timeouts hide real problems.
 */

// In the container, PLAYWRIGHT_OUTPUT_DIR is set to /test-output/playwright.
// Locally, it's unset and falls back to ./test-results (gitignored).
const OUTPUT_DIR = process.env.PLAYWRIGHT_OUTPUT_DIR || './test-results';

module.exports = defineConfig({
  testDir: './tests',
  outputDir: OUTPUT_DIR,
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: 1,
  workers: 1,
  timeout: 30 * 1000,
  expect: {
    timeout: 5 * 1000,
  },

  reporter: [
    ['list'],
    ['json', { outputFile: `${OUTPUT_DIR}/results.json` }],
  ],

  use: {
    baseURL: 'https://www.saucedemo.com',
    testIdAttribute: 'data-test',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    headless: true,
    actionTimeout: 10 * 1000,
    navigationTimeout: 15 * 1000,
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});