const { test, expect } = require('@playwright/test');
const {
    assertNoBrowserErrors,
    attachBrowserDiagnostics,
    callGameAPI,
    waitForEngine,
} = require('./test-utils');

test.describe('GDD gauntlet difficulty flow', () => {
    test('selecting a difficulty loads the first puzzle without leaving the gauntlet', async ({ page }) => {
        const diagnostics = attachBrowserDiagnostics(page);
        await page.goto('/');
        await waitForEngine(page);

        const playButton = '/root/Main/CanvasLayer/UIContainer/MainMenu/VBoxContainer/PlayButton';
        const easyButton = '/root/Main/CanvasLayer/UIContainer/MainMenu/DifficultyModal/Panel/VBoxContainer/EasyButton';
        expect(await callGameAPI(page, ['press_button', playButton])).toBe(true);
        expect(await callGameAPI(page, ['press_button', easyButton])).toBe(true);

        await expect.poll(async () => callGameAPI(page, ['get_current_mode'])).toBe(2);
        const puzzleId = await callGameAPI(page, ['get_active_puzzle_id']);
        expect(puzzleId).not.toBe('');
        const state = await callGameAPI(page, ['get_gauntlet_state']);
        expect(state.current_round).toBe(1);
        expect(state.time_left).toBeGreaterThan(0);
        expect(state.time_left).toBeLessThanOrEqual(120);
        assertNoBrowserErrors(diagnostics);
    });
});
