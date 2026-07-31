const { test, expect } = require('@playwright/test');

test.describe('Hybrid Tactical Puzzle RPG - Extended E2E', () => {

  test.beforeEach(async ({ page }) => {
    page.on('console', msg => {
      if (msg.type() === 'error') {
        console.error(`Browser console error: ${msg.text()}`);
      } else {
        console.log(`Browser log: ${msg.text()}`);
      }
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

  test('Main Menu UI Audit & Settings Interaction', async ({ page }) => {
    const canvas = page.locator('#canvas');
    await expect(canvas).toBeVisible();

    await page.waitForFunction(() => window.gameAPI !== undefined, { timeout: 30000 });
    await page.waitForTimeout(2000);

    const mode = await callGameAPI(page, ['get_current_mode']);
    expect(mode).toBe(0); // MAIN_MENU

    const btnState = await callGameAPI(page, ['get_button_state', '/root/Main/CanvasLayer/UIContainer/MainMenu/VBoxContainer/PlayButton']);
    expect(btnState).toBe(true);

    const selectState = await callGameAPI(page, ['get_button_state', '/root/Main/CanvasLayer/UIContainer/MainMenu/VBoxContainer/SelectButton']);
    expect(selectState).toBe(true);



    const settingsState = await callGameAPI(page, ['get_button_state', '/root/Main/CanvasLayer/UIContainer/MainMenu/VBoxContainer/SettingsButton']);
    expect(settingsState).toBe(true);
  });

  test('Puzzle Solving Flow', async ({ page }) => {
    await page.waitForFunction(() => window.gameAPI !== undefined, { timeout: 30000 });
    await page.waitForTimeout(2000);

    await callGameAPI(page, ['switch_mode', 2]); // ESCAPE_GAUNTLET
    await page.waitForTimeout(2000);

    let mode = await callGameAPI(page, ['get_current_mode']);
    expect(mode).toBe(2);

    // Try to auto-solve the puzzle to verify the game loop handles wins correctly
    const solveRes = await callGameAPI(page, ['solve_puzzle']);
    expect(solveRes).toBe(true);

    // Wait for the puzzle to process win state and possibly transition
    await page.waitForTimeout(4000);
  });

  test('Settings Panel Navigation', async ({ page }) => {
    await page.waitForFunction(() => window.gameAPI !== undefined, { timeout: 30000 });
    await page.waitForTimeout(2000);
    // Open settings and close (omitted here as it was empty originally)
  });

  test('Leave Button and Mark Feature E2E', async ({ page }) => {
    await page.waitForFunction(() => window.gameAPI !== undefined, { timeout: 30000 });
    await page.waitForTimeout(2000);

    // Switch to Escape Gauntlet to test Leave and Mark
    await callGameAPI(page, ['switch_mode', 2]);
    await page.waitForTimeout(2000);

    // Test Mark Feature
    // Switch to MARK mode
    // We can directly call GameManager -> mode 2 -> active_puzzle (VoxelLogic)
    await callGameAPI(page, ['press_button', '/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/VoxelLogic/CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/MarkButton']);
    await page.waitForTimeout(1000);

    // Simulate touch input for raycast to mark block (0,0,0) - simulating screen interaction
    await callGameAPI(page, ['trigger_mark_at', 0, 0, 0]);
    await page.waitForTimeout(500);

    // Test Leave Button Flow
    // 1. Click Leave
    await callGameAPI(page, ['press_button', '/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/CanvasLayer/UI/QuitButton']);
    await page.waitForTimeout(1000);

    // Assert dialog is visible
    const dialogVisible = await callGameAPI(page, ['get_node_property', '/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/CanvasLayer/UI/ConfirmDialog', 'visible']);
    expect(dialogVisible).toBe(true);

    // 2. Click No
    await callGameAPI(page, ['press_button', '/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/CanvasLayer/UI/ConfirmDialog/VBoxContainer/HBoxContainer/NoButton']);
    await page.waitForTimeout(1000);

    // Assert dialog is hidden and mode is still Gauntlet
    const dialogVisibleAfterNo = await callGameAPI(page, ['get_node_property', '/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/CanvasLayer/UI/ConfirmDialog', 'visible']);
    expect(dialogVisibleAfterNo).toBe(false);
    let mode = await callGameAPI(page, ['get_current_mode']);
    expect(mode).toBe(2);

    // 3. Click Leave again
    await callGameAPI(page, ['press_button', '/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/CanvasLayer/UI/QuitButton']);
    await page.waitForTimeout(1000);

    // 4. Click Yes
    await callGameAPI(page, ['press_button', '/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/CanvasLayer/UI/ConfirmDialog/VBoxContainer/HBoxContainer/YesButton']);
    await page.waitForTimeout(2000);

    // Assert mode changed to MAIN_MENU
    mode = await callGameAPI(page, ['get_current_mode']);
    expect(mode).toBe(0);
  });

});
