# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: gameplay.spec.js >> Hybrid Tactical Puzzle RPG - Extended E2E >> Main Menu UI Audit & Settings Interaction
- Location: tests/playwright/gameplay.spec.js:31:3

# Error details

```
Test timeout of 60000ms exceeded.
```

```
Error: page.waitForFunction: Test timeout of 60000ms exceeded.
```

# Page snapshot

```yaml
- generic [active] [ref=e1]:
  - generic [ref=e2]: Your browser does not support the canvas tag.
  - generic [ref=e3]: Failed loading file 'index.pck'
```

# Test source

```ts
  1   | const { test, expect } = require('@playwright/test');
  2   |
  3   | test.describe('Hybrid Tactical Puzzle RPG - Extended E2E', () => {
  4   |
  5   |   test.beforeEach(async ({ page }) => {
  6   |     page.on('console', msg => {
  7   |       if (msg.type() === 'error') {
  8   |         console.error(`Browser console error: ${msg.text()}`);
  9   |       } else {
  10  |         console.log(`Browser log: ${msg.text()}`);
  11  |       }
  12  |     });
  13  |     await page.goto('/');
  14  |   });
  15  |
  16  |   async function callGameAPI(page, args) {
  17  |       await page.evaluate(() => {
  18  |          window.__godot_promise = new Promise(resolve => {
  19  |             window.__godot_resolve = resolve;
  20  |          });
  21  |       });
  22  |
  23  |       await page.evaluate((a) => { window.gameAPI(a); }, args);
  24  |
  25  |       const res = await page.evaluate(async () => {
  26  |          return await window.__godot_promise;
  27  |       });
  28  |       return res;
  29  |   }
  30  |
  31  |   test('Main Menu UI Audit & Settings Interaction', async ({ page }) => {
  32  |     const canvas = page.locator('#canvas');
  33  |     await expect(canvas).toBeVisible();
  34  |
> 35  |     await page.waitForFunction(() => window.gameAPI !== undefined, { timeout: 60000 });
      |                ^ Error: page.waitForFunction: Test timeout of 60000ms exceeded.
  36  |     await page.waitForTimeout(2000);
  37  |
  38  |     const mode = await callGameAPI(page, ['get_current_mode']);
  39  |     expect(mode).toBe(0); // MAIN_MENU
  40  |
  41  |     const btnState = await callGameAPI(page, ['get_button_state', '/root/Main/CanvasLayer/UIContainer/MainMenu/VBoxContainer/PlayButton']);
  42  |     expect(btnState).toBe(true);
  43  |
  44  |     const selectState = await callGameAPI(page, ['get_button_state', '/root/Main/CanvasLayer/UIContainer/MainMenu/VBoxContainer/SelectButton']);
  45  |     expect(selectState).toBe(true);
  46  |
  47  |
  48  |
  49  |     const settingsState = await callGameAPI(page, ['get_button_state', '/root/Main/CanvasLayer/UIContainer/MainMenu/VBoxContainer/SettingsButton']);
  50  |     expect(settingsState).toBe(true);
  51  |   });
  52  |
  53  |   test('Puzzle Solving Flow', async ({ page }) => {
  54  |     await page.waitForFunction(() => window.gameAPI !== undefined, { timeout: 60000 });
  55  |     await page.waitForTimeout(2000);
  56  |
  57  |     await callGameAPI(page, ['switch_mode', 2]); // ESCAPE_GAUNTLET
  58  |     await page.waitForTimeout(2000);
  59  |
  60  |     let mode = await callGameAPI(page, ['get_current_mode']);
  61  |     expect(mode).toBe(2);
  62  |
  63  |     // Try to auto-solve the puzzle to verify the game loop handles wins correctly
  64  |     const solveRes = await callGameAPI(page, ['solve_puzzle']);
  65  |     expect(solveRes).toBe(true);
  66  |
  67  |     // Wait for the puzzle to process win state and possibly transition
  68  |     await page.waitForTimeout(4000);
  69  |   });
  70  |
  71  |   test('Settings Panel Navigation', async ({ page }) => {
  72  |     await page.waitForFunction(() => window.gameAPI !== undefined, { timeout: 60000 });
  73  |     await page.waitForTimeout(2000);
  74  |     // Open settings and close (omitted here as it was empty originally)
  75  |   });
  76  |
  77  |   test('Leave Button and Mark Feature E2E', async ({ page }) => {
  78  |     await page.waitForFunction(() => window.gameAPI !== undefined, { timeout: 60000 });
  79  |     await page.waitForTimeout(2000);
  80  |
  81  |     // Switch to Escape Gauntlet to test Leave and Mark
  82  |     await callGameAPI(page, ['switch_mode', 2]);
  83  |     await page.waitForTimeout(2000);
  84  |
  85  |     // Test Mark Feature
  86  |     // We can directly call GameManager -> mode 2 -> active_puzzle (VoxelLogic)
  87  |     await callGameAPI(page, ['press_button', '/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/VoxelLogic/CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/MarkButton']);
  88  |     await page.waitForTimeout(1000);
  89  |
  90  |     // Simulate touch input for raycast to mark block (0,0,0) - simulating screen interaction
  91  |     await callGameAPI(page, ['trigger_mark_at', 0, 0, 0]);
  92  |     await page.waitForTimeout(500);
  93  |
  94  |     // Test Leave Button Flow via direct node property checking to ensure visual state changes are unblocked
  95  |     await callGameAPI(page, ['press_button', '/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/CanvasLayer/UI/QuitButton']);
  96  |     await page.waitForTimeout(1000);
  97  |
  98  |     // Assert dialog is visible
  99  |     const dialogVisible = await callGameAPI(page, ['get_node_property', '/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/CanvasLayer/UI/ConfirmDialog', 'visible']);
  100 |     expect(dialogVisible).toBe(true);
  101 |
  102 |     // Click No via bridge
  103 |     await callGameAPI(page, ['press_button', '/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/CanvasLayer/UI/ConfirmDialog/VBoxContainer/HBoxContainer/NoButton']);
  104 |     await page.waitForTimeout(1000);
  105 |
  106 |     // Assert dialog is hidden and mode is still Gauntlet
  107 |     const dialogVisibleAfterNo = await callGameAPI(page, ['get_node_property', '/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/CanvasLayer/UI/ConfirmDialog', 'visible']);
  108 |     expect(dialogVisibleAfterNo).toBe(false);
  109 |     let mode = await callGameAPI(page, ['get_current_mode']);
  110 |     expect(mode).toBe(2);
  111 |
  112 |     // Click Leave again via bridge
  113 |     await callGameAPI(page, ['press_button', '/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/CanvasLayer/UI/QuitButton']);
  114 |     await page.waitForTimeout(1000);
  115 |
  116 |     // Click Yes via bridge
  117 |     await callGameAPI(page, ['press_button', '/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/CanvasLayer/UI/ConfirmDialog/VBoxContainer/HBoxContainer/YesButton']);
  118 |     await page.waitForTimeout(2000);
  119 |
  120 |     // Assert mode changed to MAIN_MENU
  121 |     mode = await callGameAPI(page, ['get_current_mode']);
  122 |     expect(mode).toBe(0);
  123 |   });
  124 |
  125 |   test('New Grid Interactions & Slicing E2E', async ({ page }) => {
  126 |     await page.waitForFunction(() => window.gameAPI !== undefined, { timeout: 60000 });
  127 |     await page.waitForTimeout(2000);
  128 |
  129 |     // Switch to Escape Gauntlet to test new mechanics
  130 |     await callGameAPI(page, ['switch_mode', 2]);
  131 |     await page.waitForTimeout(2000);
  132 |
  133 |     // Test changing to paint mode
  134 |     await callGameAPI(page, ['set_edit_mode', 'paint']);
  135 |     await page.waitForTimeout(500);
```