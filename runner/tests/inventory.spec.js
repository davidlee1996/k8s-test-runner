// @ts-check
const { test, expect } = require('@playwright/test');
const { getUserForThisRun } = require('./fixtures/users');

const user = getUserForThisRun();

/**
 * Inventory and cart tests — only meaningful for users that can log in.
 *
 * Behavior per user:
 *   STANDARD            → can add to cart, cart count updates correctly
 *   PROBLEM             → can add to cart, but expect known bugs
 *   PERFORMANCE_GLITCH  → works correctly, but slowly
 *   LOCKED_OUT          → skipped (can't log in)
 */

test.describe(`Inventory & cart [${user.key}]`, () => {
  test.beforeEach(async ({ page }) => {
    test.skip(!user.expectations.canLogin, `${user.key} cannot log in, skipping inventory tests`);

    await page.goto('/');
    await page.getByTestId('username').fill(user.username);
    await page.getByTestId('password').fill(user.password);
    await page.getByTestId('login-button').click();
    await expect(page).toHaveURL(/.*inventory\.html/, { timeout: 15000 });
  });

  test('inventory page lists at least 6 products', async ({ page }) => {
    const items = page.getByTestId('inventory-item');
    const count = await items.count();
    expect(count).toBeGreaterThanOrEqual(6);
  });

  test('adding a product to cart updates the cart badge', async ({ page }) => {
    const firstAddButton = page.locator('[data-test^="add-to-cart"]').first();
    await firstAddButton.click();

    if (user.expectations.cartWorks) {
      const badge = page.getByTestId('shopping-cart-badge');
      await expect(badge).toBeVisible();
      await expect(badge).toHaveText('1');
    } else {
      // problem_user: cart may behave unexpectedly. Document, don't strictly assert.
      const badge = page.getByTestId('shopping-cart-badge');
      const badgeVisible = await badge.isVisible().catch(() => false);
      console.log(`[${user.key}] cart badge visible after add: ${badgeVisible}`);
    }
  });

  test('product page is reachable from inventory', async ({ page }) => {
    const firstProduct = page.locator('.inventory_item_name').first();
    const productName = await firstProduct.textContent();
    await firstProduct.click();

    await expect(page).toHaveURL(/.*inventory-item\.html/);

    const detailName = page.locator('.inventory_details_name');
    await expect(detailName).toHaveText(productName.trim());
  });
});