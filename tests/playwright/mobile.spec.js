'use strict';

const { test, expect } = require('@playwright/test');
const {
    assertCanvasRendered,
    assertNoBrowserErrors,
    attachBrowserDiagnostics,
    callGameAPI,
    waitForEngine,
} = require('./test-utils');

test.describe('Mobile touch smoke test', () => {
    let diagnostics;

    test.beforeEach(async ({ page }) => {
        diagnostics = attachBrowserDiagnostics(page);
        await page.goto('/');
    });

    test('renders and accepts touch-capable mobile navigation', async ({ page }) => {
        expect(await page.evaluate(() => navigator.maxTouchPoints > 0 || 'ontouchstart' in window)).toBe(true);

        await waitForEngine(page);
        const stats = await assertCanvasRendered(page);
        expect(stats.width).toBeGreaterThan(0);
        expect(stats.height).toBeGreaterThan(0);
        expect(await callGameAPI(page, ['get_current_mode'])).toBe(0);

        await callGameAPI(page, ['switch_mode', 4]);
        await page.waitForTimeout(1500);
        expect(await callGameAPI(page, ['get_current_mode'])).toBe(4);
        await assertCanvasRendered(page);
        assertNoBrowserErrors(diagnostics);
    });
});
