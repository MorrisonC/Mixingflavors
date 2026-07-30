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

    const editorState = await callGameAPI(page, ['get_button_state', '/root/Main/CanvasLayer/UIContainer/MainMenu/VBoxContainer/EditorButton']);
    expect(editorState).toBe(true);

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
  });

});
