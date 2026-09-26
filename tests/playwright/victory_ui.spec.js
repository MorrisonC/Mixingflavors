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
    // load_tutorial_puzzle opens the standalone puzzle scene directly; the
    // gauntlet scene is covered by difficulty_flow.spec.js.
    expect(mode).toBe(1);
    expect(await callGameAPI(page, ['get_active_puzzle_id'])).toBe('tutorial_star');

    // Solve the Tutorial puzzle via TestBridge API
    const solveRes = await callGameAPI(page, ['solve_puzzle']);
    expect(solveRes).toBe(true);

    // Wait for the reveal timer without assuming a fixed headless frame rate.
    await expect.poll(async () => {
      const state = await callGameAPI(page, ['get_victory_state']);
      return state.found && state.visible && state.snapshot && state.snapshot.score > 0;
    }, { timeout: 15000, intervals: [250, 500, 1000] }).toBe(true);
    const victoryState = await callGameAPI(page, ['get_victory_state']);
    expect(victoryState.snapshot.score).toBeGreaterThan(0);
    expect(victoryState.snapshot.stars).toBeGreaterThanOrEqual(1);
    expect(victoryState.snapshot.time_seconds).toBeGreaterThanOrEqual(0);
    const replayPath = '/root/Main/SubViewportContainer/SubViewport/VoxelLogic/CanvasLayer/VictoryScreen/Background/PanelContainer/VBoxContainer/ActionRow/ReplayButton';
    const sharePath = '/root/Main/SubViewportContainer/SubViewport/VoxelLogic/CanvasLayer/VictoryScreen/Background/PanelContainer/VBoxContainer/ActionRow/ShareButton';
    expect(await callGameAPI(page, ['get_node_property', replayPath, 'disabled'])).toBe(false);
    expect(await callGameAPI(page, ['get_node_property', sharePath, 'disabled'])).toBe(true);
  });
});
