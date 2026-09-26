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

  test('Switch to Level Select, start a validated puzzle, check Leave confirmation prompt', async ({ page }) => {
    await waitForEngine(page);

    // 1. Switch to Level Select mode (GameMode.PUZZLE_SELECTION = 4)
    await callGameAPI(page, ['switch_mode', 4]);
    await page.waitForTimeout(2000);
    expect(await callGameAPI(page, ['get_current_mode'])).toBe(4);

    // 2. Load the canonical tutorial puzzle. The previous ad-hoc fixture had
    // no unique solution and only passed because the rejected grid stayed
    // inactive, which made this test falsely green.
    expect(await callGameAPI(page, ['load_tutorial_puzzle'])).toBe(true);
    await page.waitForTimeout(2000);

    // 3. Verify the validated puzzle is actually active.
    expect(await callGameAPI(page, ['get_active_puzzle_id'])).toBe('tutorial_star');
    const isChiseled = await callGameAPI(page, ['is_cell_chiseled', 0, 0, 0]);
    expect(isChiseled).toBe(false);

    // 4. Exercise the standalone leave confirmation instead of only testing
    // that a button node exists.
    const leavePath = '/root/Main/SubViewportContainer/SubViewport/VoxelLogic/CanvasLayer/Control/MarginContainer/TopRowContainer/LeaveButton';
    expect(await callGameAPI(page, ['press_button', leavePath])).toBe(true);
    const confirmPath = '/root/Main/SubViewportContainer/SubViewport/VoxelLogic/CanvasLayer/Control/ConfirmDialog';
    expect(await callGameAPI(page, ['get_node_property', confirmPath, 'visible'])).toBe(true);
    const noPath = confirmPath + '/MarginContainer/VBoxContainer/HBoxContainer/NoButton';
    expect(await callGameAPI(page, ['press_button', noPath])).toBe(true);
    expect(await callGameAPI(page, ['get_node_property', confirmPath, 'visible'])).toBe(false);
  });
});
