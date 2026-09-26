const { test, expect } = require('@playwright/test');
const {
    assertNoBrowserErrors,
    attachBrowserDiagnostics,
    callGameAPI,
    waitForEngine,
} = require('./test-utils');

test.describe('Voxel archive flow', () => {
    test('archive button opens the persistent collection screen', async ({ page }) => {
        const diagnostics = attachBrowserDiagnostics(page);
        await page.goto('/');
        await waitForEngine(page);
        const archiveButton = '/root/Main/CanvasLayer/UIContainer/MainMenu/VBoxContainer/ArchiveButton';
        expect(await callGameAPI(page, ['press_button', archiveButton])).toBe(true);
        await expect.poll(async () => callGameAPI(page, ['get_current_mode'])).toBe(6);
        expect(await callGameAPI(page, ['get_node_property', '/root/Main/CanvasLayer/UIContainer/ArchiveScreen', 'visible'])).toBe(true);
        assertNoBrowserErrors(diagnostics);
    });
});
