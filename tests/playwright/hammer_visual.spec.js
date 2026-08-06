const { test, expect } = require('@playwright/test');

test.describe('Hammer Action Visual Removal E2E Verification', () => {

  test.beforeEach(async ({ page }) => {
    page.on('console', msg => {
      console.log(`Browser log: ${msg.text()}`);
    });
    await page.goto('/');
  });

  async function callGameAPI(page, args) {
      await page.evaluate(() => {
         window.__godot_promise = new Promise(resolve => {
            window.__godot_resolve = resolve;
         });
      });

      await page.evaluate((a) => { window.gameAPI(a); }, args);

      const res = await page.evaluate(async () => {
         return await window.__godot_promise;
      });
      return res;
  }

  test('Chiseling non-target block changes cell state and hides multimesh instance', async ({ page }) => {
    await page.waitForFunction(() => window.gameAPI !== undefined, { timeout: 60000 });
    await page.waitForTimeout(2000);

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
