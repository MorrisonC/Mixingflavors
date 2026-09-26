const { test, expect } = require('@playwright/test');
const {
    assertNoBrowserErrors,
    attachBrowserDiagnostics,
    callGameAPI,
    waitForEngine,
} = require('./test-utils');

test.describe('Daily Challenge flow', () => {
    test('starts a deterministic daily run without requiring a network', async ({ page }) => {
        const diagnostics = attachBrowserDiagnostics(page);
        await page.goto('/');
        await waitForEngine(page);
        const dailyButton = '/root/Main/CanvasLayer/UIContainer/MainMenu/VBoxContainer/DailyButton';
        expect(await callGameAPI(page, ['press_button', dailyButton])).toBe(true);
        await expect.poll(async () => callGameAPI(page, ['get_current_mode'])).toBe(2);
        const state = await callGameAPI(page, ['get_gauntlet_state']);
        expect(state.current_round).toBe(1);
        expect(state.time_left).toBeGreaterThan(0);
        expect(state.time_left).toBeLessThanOrEqual(120);
        expect(await callGameAPI(page, ['get_active_puzzle_id'])).not.toBe('');
        assertNoBrowserErrors(diagnostics);
    });
});
