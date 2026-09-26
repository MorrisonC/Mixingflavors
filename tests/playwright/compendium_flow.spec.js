const { test, expect } = require('@playwright/test');
const {
    assertNoBrowserErrors,
    attachBrowserDiagnostics,
    callGameAPI,
    waitForEngine,
} = require('./test-utils');

const SELECT_BUTTON = '/root/Main/CanvasLayer/UIContainer/MainMenu/VBoxContainer/SelectButton';
const MODE_COMENDIUM = 4;
const PUZZLE_TUTORIAL = '/root/Main/CanvasLayer/UIContainer/PuzzleSelection/HBoxContainer/PuzzlePanel/ScrollContainer/PuzzleGrid/Puzzle_tutorial_star';

test.describe('Compendium completion persistence', () => {
    test('a solved tutorial remains mastered after returning and reloading', async ({ page }) => {
        const diagnostics = attachBrowserDiagnostics(page);
        await page.goto('/');
        await waitForEngine(page);

        expect(await callGameAPI(page, ['press_button', SELECT_BUTTON])).toBe(true);
        await expect.poll(async () => callGameAPI(page, ['get_current_mode'])).toBe(MODE_COMENDIUM);
        expect(await callGameAPI(page, ['press_button', PUZZLE_TUTORIAL])).toBe(true);
        await expect.poll(async () => callGameAPI(page, ['get_current_mode'])).toBe(1);
        expect(await callGameAPI(page, ['get_active_puzzle_id'])).toBe('tutorial_star');
        expect(await callGameAPI(page, ['solve_puzzle'])).toBe(true);

        await expect.poll(async () => {
            const completion = await callGameAPI(page, ['get_completion']);
            return completion && completion.tutorial_star ? completion.tutorial_star.stars : 0;
        }, { timeout: 20000 }).toBeGreaterThan(0);

        expect(await callGameAPI(page, ['switch_mode', MODE_COMENDIUM])).toBe(true);
        await expect.poll(async () => callGameAPI(page, ['get_current_mode'])).toBe(MODE_COMENDIUM);
        const buttonText = await callGameAPI(page, ['get_node_property', PUZZLE_TUTORIAL, 'text']);
        expect(buttonText).toContain('★');

        await page.reload();
        await waitForEngine(page);
        expect(await callGameAPI(page, ['press_button', SELECT_BUTTON])).toBe(true);
        await expect.poll(async () => callGameAPI(page, ['get_current_mode'])).toBe(MODE_COMENDIUM);
        const persistedText = await callGameAPI(page, ['get_node_property', PUZZLE_TUTORIAL, 'text']);
        expect(persistedText).toContain('★');
        assertNoBrowserErrors(diagnostics);
    });
});
