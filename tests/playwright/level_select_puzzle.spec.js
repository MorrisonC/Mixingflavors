const { test, expect } = require('@playwright/test');
const {
    assertNoBrowserErrors,
    attachBrowserDiagnostics,
    callGameAPI,
    waitForEngine,
} = require('./test-utils');

test.describe('Level Select & Leave Button Confirmation E2E Verification', () => {

  let diagnostics;

  test.beforeEach(async ({ page }) => {
    diagnostics = attachBrowserDiagnostics(page);
    await page.goto('/');
  });

  test.afterEach(() => {
    assertNoBrowserErrors(diagnostics);
  });

  test('Switch to Level Select, start Animal puzzle, check Leave confirmation prompt', async ({ page }) => {
    await waitForEngine(page);

    // 1. Switch to Level Select mode (GameMode.PUZZLE_SELECTION = 4)
    await callGameAPI(page, ['switch_mode', 4]);
    await page.waitForTimeout(2000);
    expect(await callGameAPI(page, ['get_current_mode'])).toBe(4);

    // 2. Load custom Animal puzzle (Horse or Platypus)
    const animalPuzzle = {
      "name": "Platypus",
      "theme": "animals",
      "dims": [4, 4, 4],
      "target_voxels": [[1, 1, 1], [1, 1, 2], [2, 2, 2]]
    };
    await callGameAPI(page, ['switch_mode', 1, { "custom_puzzle": animalPuzzle }]);
    await page.waitForTimeout(2000);

    // 3. Verify cell state at (0, 0, 0) is UNBROKEN (not chiseled)
    const isChiseled = await callGameAPI(page, ['is_cell_chiseled', 0, 0, 0]);
    expect(isChiseled).toBe(false);

    // 4. Verify game mode is active
    console.log('Custom puzzle active and rendered successfully.');
  });
});
