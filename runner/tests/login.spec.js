// @ts-check
const { test, expect } = require('@playwright/test');
const { USERS } = require('./fixtures/users');

/**
 * Login flow tests against saucedemo.com.
 *
 * Selector strategy: data-test attributes via getByTestId().
 * Sauce demo exposes data-test="..." on every interactive element.
 * These are stable across UI refactors.
 */

test.describe('Login flow', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('standard user can log in and reach inventory', async ({ page }) => {
    const usernameInput = page.getByTestId('username');
    const passwordInput = page.getByTestId('password');
    const loginButton = page.getByTestId('login-button');

    await usernameInput.fill(USERS.STANDARD.username);
    await passwordInput.fill(USERS.STANDARD.password);
    await loginButton.click();

    await expect(page).toHaveURL(/.*inventory\.html/);
    await expect(page.getByTestId('title')).toHaveText('Products');

    const inventoryItems = page.getByTestId('inventory-item');
    await expect(inventoryItems.first()).toBeVisible();
    expect(await inventoryItems.count()).toBeGreaterThan(0);
  });

  test('locked-out user sees error message', async ({ page }) => {
    await page.getByTestId('username').fill(USERS.LOCKED_OUT.username);
    await page.getByTestId('password').fill(USERS.LOCKED_OUT.password);
    await page.getByTestId('login-button').click();

    const error = page.getByTestId('error');
    await expect(error).toBeVisible();
    await expect(error).toContainText('locked out');
  });
});