const { test, expect } = require('@playwright/test');
const {
    assertNoBrowserErrors,
    attachBrowserDiagnostics,
    callGameAPI,
    waitForEngine,
} = require('./test-utils');

test.describe('Tutorial Level & Victory Screen UI Verification', () => {

  let diagnostics;

  test.beforeEach(async ({ page }) => {
    diagnostics = attachBrowserDiagnostics(page);
    await page.goto('/');
  });

  test.afterEach(() => {
    assertNoBrowserErrors(diagnostics);
  });

  test('Tutorial Level puzzle load, solve & victory screen UI assertion', async ({ page }) => {
    await waitForEngine(page);

    // Load specifically the Tutorial Star Level payload
    const loadTutorialRes = await callGameAPI(page, ['load_tutorial_puzzle']);
    expect(loadTutorialRes).toBe(true);
    await page.waitForTimeout(2000);

    const mode = await callGameAPI(page, ['get_current_mode']);
    expect(mode).toBe(2);

    // Solve the Tutorial puzzle via TestBridge API
    const solveRes = await callGameAPI(page, ['solve_puzzle']);
    expect(solveRes).toBe(true);

    // Wait for model reveal animation and 2-second timeout before VictoryScreen instantiates
    await page.waitForTimeout(3500);

    // Assert that VictoryScreen UI is visible in the Tutorial level scene
    const victoryNode = await callGameAPI(page, ['get_node_property', '/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/VoxelLogic/CanvasLayer/VictoryScreen', 'visible']);
    expect(victoryNode).not.toBeNull();
  });
});
