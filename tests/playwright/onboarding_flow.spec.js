const { test, expect } = require('@playwright/test');
const {
    assertNoBrowserErrors,
    attachBrowserDiagnostics,
    callGameAPI,
    waitForEngine,
} = require('./test-utils');

test.describe('Onboarding entry point', () => {
    test('How to Play shows written rules, then opens the semantic tutorial puzzle', async ({ page }) => {
        const diagnostics = attachBrowserDiagnostics(page);
        await page.goto('/');
        await waitForEngine(page);
        const button = '/root/Main/CanvasLayer/UIContainer/MainMenu/VBoxContainer/TutorialButton';
        expect(await callGameAPI(page, ['press_button', button])).toBe(true);

        // The rules must appear first, and the menu must not jump straight into
        // a timed puzzle behind the player's back.
        const modalPath = '/root/Main/CanvasLayer/UIContainer/MainMenu/HowToPlayModal';
        await expect.poll(async () => callGameAPI(page, ['get_node_property', modalPath, 'visible'])).toBe(true);
        expect(await callGameAPI(page, ['get_current_mode'])).toBe(0);

        const startPath = `${modalPath}/Panel/Margin/VBoxContainer/ActionRow/StartPracticeButton`;
        expect(await callGameAPI(page, ['press_button', startPath])).toBe(true);
        await expect.poll(async () => callGameAPI(page, ['get_current_mode'])).toBe(1);
        expect(await callGameAPI(page, ['get_active_puzzle_id'])).toBe('tutorial_star');
        assertNoBrowserErrors(diagnostics);
    });

    test('How to Play rules can be dismissed without starting a run', async ({ page }) => {
        const diagnostics = attachBrowserDiagnostics(page);
        await page.goto('/');
        await waitForEngine(page);
        const modalPath = '/root/Main/CanvasLayer/UIContainer/MainMenu/HowToPlayModal';
        expect(await callGameAPI(page, ['press_button', '/root/Main/CanvasLayer/UIContainer/MainMenu/VBoxContainer/TutorialButton'])).toBe(true);
        await expect.poll(async () => callGameAPI(page, ['get_node_property', modalPath, 'visible'])).toBe(true);

        expect(await callGameAPI(page, ['press_button', `${modalPath}/Panel/Margin/VBoxContainer/ActionRow/BackButton`])).toBe(true);
        await expect.poll(async () => callGameAPI(page, ['get_node_property', modalPath, 'visible'])).toBe(false);
        expect(await callGameAPI(page, ['get_current_mode'])).toBe(0);
        assertNoBrowserErrors(diagnostics);
    });

    test('the guided banner is readable below the puzzle HUD', async ({ page }) => {
        const diagnostics = attachBrowserDiagnostics(page);
        await page.goto('/');
        await waitForEngine(page);
        expect(await callGameAPI(page, ['press_button', '/root/Main/CanvasLayer/UIContainer/MainMenu/VBoxContainer/TutorialButton'])).toBe(true);
        expect(await callGameAPI(page, ['press_button', '/root/Main/CanvasLayer/UIContainer/MainMenu/HowToPlayModal/Panel/Margin/VBoxContainer/ActionRow/StartPracticeButton'])).toBe(true);
        await expect.poll(async () => callGameAPI(page, ['get_current_mode'])).toBe(1);
        await page.waitForTimeout(1500);

        // The banner used to be laid out on top of the puzzle's own top bar, so
        // the instruction was painted underneath it and read as absent.
        const rects = await callGameAPI(page, ['get_ui_rects']);
        const byName = Object.fromEntries((rects.rects || []).map((entry) => [entry.name, entry]));
        const hud = byName.LeaveButton;
        const banner = byName.TutorialBannerPanel;
        expect(hud, 'the puzzle HUD leave button should be reported').toBeTruthy();
        expect(banner, 'the instruction banner should be reported').toBeTruthy();
        expect(banner.visible, 'the tutorial overlay must be on screen').toBe(true);
        expect(banner.h, 'the banner needs real height to hold an instruction').toBeGreaterThan(40);
        expect(banner.y, 'the banner must start below the HUD, not on top of it').toBeGreaterThan(hud.y + hud.h - 1);
        assertNoBrowserErrors(diagnostics);
    });
});
