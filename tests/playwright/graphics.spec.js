'use strict';

const { test, expect } = require('@playwright/test');
const {
    assertCanvasRendered,
    assertNoBrowserErrors,
    assertNoUnexpectedWebGlWarnings,
    attachBrowserDiagnostics,
    callGameAPI,
    waitForEngine,
} = require('./test-utils');

const viewports = [
    { name: 'Mobile', width: 375, height: 812 },
    { name: 'Desktop', width: 1920, height: 1080 },
    { name: 'Ultrawide', width: 2560, height: 1080 },
];

test.describe('Graphics QA - Visual Regression', () => {
    let diagnostics;

    test.beforeEach(async ({ page }) => {
        diagnostics = attachBrowserDiagnostics(page);
        await page.goto('/');
    });

    for (const viewport of viewports) {
        test(`Main Menu Snapshot - ${viewport.name}`, async ({ page }) => {
            await page.setViewportSize({ width: viewport.width, height: viewport.height });
            await waitForEngine(page);
            await assertCanvasRendered(page);
            await page.waitForTimeout(1000);

            await callGameAPI(page, ['pause_engine']);
            expect(await page.screenshot()).toMatchSnapshot(`main-menu-${viewport.name.toLowerCase()}.png`, { maxDiffPixels: 10000 });
            await callGameAPI(page, ['unpause_engine']);

            assertNoBrowserErrors(diagnostics);
            assertNoUnexpectedWebGlWarnings(diagnostics);
        });

        test(`Level Select Snapshot - ${viewport.name}`, async ({ page }) => {
            await page.setViewportSize({ width: viewport.width, height: viewport.height });
            await waitForEngine(page);
            await callGameAPI(page, ['switch_mode', 4]);
            await page.waitForTimeout(2000);
            await assertCanvasRendered(page);

            await callGameAPI(page, ['pause_engine']);
            expect(await page.screenshot()).toMatchSnapshot(`level-select-${viewport.name.toLowerCase()}.png`, { maxDiffPixels: 10000 });
            await callGameAPI(page, ['unpause_engine']);

            assertNoBrowserErrors(diagnostics);
            assertNoUnexpectedWebGlWarnings(diagnostics);
        });

        test(`Gameplay View Snapshot - ${viewport.name}`, async ({ page }) => {
            await page.setViewportSize({ width: viewport.width, height: viewport.height });
            await waitForEngine(page);
            await callGameAPI(page, ['switch_mode', 2]);
            await page.waitForTimeout(3000);
            await assertCanvasRendered(page);

            await callGameAPI(page, ['pause_engine']);
            expect(await page.screenshot()).toMatchSnapshot(`gameplay-view-${viewport.name.toLowerCase()}.png`, { maxDiffPixels: 10000 });
            await callGameAPI(page, ['unpause_engine']);

            assertNoBrowserErrors(diagnostics);
            assertNoUnexpectedWebGlWarnings(diagnostics);
        });
    }
});
