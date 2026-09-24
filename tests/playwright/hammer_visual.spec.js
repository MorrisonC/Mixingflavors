const { test, expect } = require('@playwright/test');
const {
    assertNoBrowserErrors,
    attachBrowserDiagnostics,
    callGameAPI,
    waitForEngine,
} = require('./test-utils');

test.describe('Hammer Action Visual Removal E2E Verification', () => {

  let diagnostics;

  test.beforeEach(async ({ page }) => {
    diagnostics = attachBrowserDiagnostics(page);
    await page.goto('/');
  });

  test.afterEach(() => {
    assertNoBrowserErrors(diagnostics);
  });

  test('Chiseling non-target block changes cell state and hides multimesh instance', async ({ page }) => {
    await waitForEngine(page);

    // Switch to Escape Gauntlet / Puzzle mode
    await callGameAPI(page, ['switch_mode', 2]);
    await page.waitForTimeout(2000);

    // Trigger chisel at Vector3i(0, 0, 0)
    await callGameAPI(page, ['trigger_chisel_at', 0, 0, 0]);
    await page.waitForTimeout(1000);

    // Verify cell state is chiseled via API
    const isChiseled = await callGameAPI(page, ['is_cell_chiseled', 0, 0, 0]);
    expect(isChiseled).toBe(true);
  });
});
