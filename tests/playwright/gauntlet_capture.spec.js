const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

test.describe('Gauntlet Capture', () => {

  test.beforeEach(async ({ page }) => {
    page.on('console', msg => {
      // hide missing gl errors
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

  async function waitForEngine(page) {
    await page.waitForFunction(() => window.gameAPI !== undefined, { timeout: 60000 });
    await page.waitForTimeout(2000);
  }

  async function takeScreenshot(page, filename, vpName) {
    const cycleDir = process.env.CYCLE_DIR || 'cycle_00';
    const filepath = path.join(__dirname, '..', '..', 'gauntlet_runs', cycleDir, `${filename}-${vpName}.png`);

    // Ensure dir exists
    const dir = path.dirname(filepath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    // Wait for rendering to stabilize
    await page.waitForTimeout(2000);

    // Pause engine so canvas is stable
    // pause removed
    await page.screenshot({ path: filepath });
    // unpause removed
    console.log(`Saved screenshot: ${filepath}`);
  }

  const viewports = [
    { name: 'Desktop', width: 1920, height: 1080 },
    { name: 'Mobile', width: 375, height: 812 }
  ];

  for (const vp of viewports) {
    test(`Capture All States - ${vp.name}`, async ({ page }) => {
      test.setTimeout(180000); // 3 mins per viewport
      await page.setViewportSize({ width: vp.width, height: vp.height });
      await waitForEngine(page);

      // 1. Main Menu
      await callGameAPI(page, ['switch_mode', 0]); // MAIN_MENU
      await page.waitForTimeout(2000);
      await takeScreenshot(page, '01-main-menu', vp.name);

      // 2. Settings
      await callGameAPI(page, ['click_ui_button', 'SettingsButton']);
      await page.waitForTimeout(1000);
      await takeScreenshot(page, '02-settings', vp.name);

      // We can click Close on settings
      await callGameAPI(page, ['click_ui_button', 'CloseButton']);
      await page.waitForTimeout(1000);

      // 3. Puzzle Selection
      await callGameAPI(page, ['switch_mode', 4]); // PUZZLE_SELECTION
      await page.waitForTimeout(3000);
      await takeScreenshot(page, '03-puzzle-selection', vp.name);

      // 4. Escape Gauntlet
      await callGameAPI(page, ['switch_mode', 2]); // ESCAPE_GAUNTLET
      await page.waitForTimeout(4000);
      await takeScreenshot(page, '04-escape-gauntlet', vp.name);

      // 5. Gallery
      await callGameAPI(page, ['change_scene', 'res://scenes/GalleryScreen.tscn']);
      await page.waitForTimeout(3000);
      await takeScreenshot(page, '05-gallery', vp.name);

      // Go back to main
      await callGameAPI(page, ['change_scene', 'res://scenes/Main.tscn']);
      await waitForEngine(page);

      // 6. Victory Screen
      await callGameAPI(page, ['load_tutorial_puzzle']);
      await page.waitForTimeout(2000);
      await callGameAPI(page, ['solve_puzzle']);
      await page.waitForTimeout(4000);
      await takeScreenshot(page, '06-victory-screen', vp.name);
    });
  }
});
