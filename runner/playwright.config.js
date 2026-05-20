// @ts-check
const { defineConfig, devices } = require('@playwright/test');

/**
 * Playwright config for k8s-test-runner.
 *
 * Key choices:
 * - testIdAttribute: 'data-test' — saucedemo uses data-test (not data-testid).
 *   Setting this lets getByTestId() find the elements.
 * - PLAYWRIGHT_OUTPUT_DIR env var: in container, /test-output/playwright.
 *   Locally, falls back to ./test-results.
 * - workers: 1 inside each container. Parallelism comes from K8s, not Playwright.
 * - retries: 1. Containerized parallel runs should fail fast.
 */

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