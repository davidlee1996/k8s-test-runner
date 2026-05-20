// @ts-check
const { test, expect } = require('@playwright/test');
const { getUserForThisRun } = require('./fixtures/users');

const user = getUserForThisRun();

/**
 * Login tests, parameterized by the SAUCE_USER env var.
 *
 * Behavior changes per user:
 *   STANDARD            → login succeeds, lands on inventory
 *   LOCKED_OUT          → login fails with "locked out" error
 *   PROBLEM             → login succeeds (cart bugs surface later)
 *   PERFORMANCE_GLITCH  → login succeeds, but takes ~5s
 *
 * The test asserts whichever outcome is contractually expected for this user.
 * That's what makes per-user sharding meaningful.
 */

test.describe(`Login flow [${user.key}]`, () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('login behaves as expected for this user', async ({ page }) => {
    await page.getByTestId('username').fill(user.username);
    await page.getByTestId('password').fill(user.password);
    await page.getByTestId('login-button').click();

    if (user.expectations.canLogin) {
      // Expect to reach the inventory page
      await expect(page).toHaveURL(/.*inventory\.html/, { timeout: 15000 });
      await expect(page.getByTestId('title')).toHaveText('Products');

      const inventoryItems = page.getByTestId('inventory-item');
      await expect(inventoryItems.first()).toBeVisible();
      expect(await inventoryItems.count()).toBeGreaterThan(0);
    } else {
      // Expect login to fail with locked-out error
      const error = page.getByTestId('error');
      await expect(error).toBeVisible();
      if (user.expectations.lockoutErrorVisible) {
        await expect(error).toContainText('locked out');
      }
    }
  });
});