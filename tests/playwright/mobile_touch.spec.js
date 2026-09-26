'use strict';

// A genuine touch test against the real puzzle scene.
//
// The existing mobile smoke test navigates to the puzzle-selection screen and
// never instantiates VoxelLogic, so no toolbar, camera, or touch Control is
// ever built. It would pass with the entire touch layer deleted. This spec
// loads a real puzzle and drives it with dispatched touch events, which is the
// only layer that can catch toolbar fall-through, swallowed taps, and controls
// that are unreachable or overlapping on a short landscape phone.

const { test, expect } = require('@playwright/test');
const {
    assertCanvasRendered,
    assertNoBrowserErrors,
    attachBrowserDiagnostics,
    callGameAPI,
    waitForEngine,
} = require('./test-utils');

const TUTORIAL_PATH = 'res://data/puzzles/tutorial_star.json';

async function loadPuzzle(page) {
    await callGameAPI(page, ['load_tutorial_puzzle', TUTORIAL_PATH]);
    // The puzzle scene, camera fit, and toolbar all build over a few frames.
    await page.waitForFunction(
        () => document.getElementById('canvas') !== null,
        undefined,
        { timeout: 15000 },
    );
    await page.waitForTimeout(2500);
}

/** Converts a normalized viewport point to CSS pixels over the canvas. */
async function toPagePoint(page, nx, ny) {
    const box = await page.evaluate(() => {
        const canvas = document.getElementById('canvas');
        if (!canvas) {
            return null;
        }
        const rect = canvas.getBoundingClientRect();
        return { x: rect.left, y: rect.top, width: rect.width, height: rect.height };
    });
    if (!box) {
        return null;
    }
    return { x: box.x + nx * box.width, y: box.y + ny * box.height };
}

/**
 * Finds a screen point that the GAME's own hit test resolves to an unbroken
 * non-target voxel. Using the real raycast means the test proves the shipping
 * input path rather than a reimplementation of the projection maths.
 */
async function findTappablePoint(page) {
    const candidates = [];
    for (let gx = 0; gx < 3; gx += 1) {
        for (let gy = 0; gy < 3; gy += 1) {
            for (let gz = 0; gz < 3; gz += 1) {
                const projected = await callGameAPI(page, ['get_cell_screen_pos', gx, gy, gz]);
                if (!projected || projected.ok !== true || projected.behind === true) {
                    continue;
                }
                candidates.push({ nx: projected.x, ny: projected.y });
            }
        }
    }
    for (const candidate of candidates) {
        const hit = await callGameAPI(page, ['get_cell_at_normalized_pos', candidate.nx, candidate.ny]);
        if (!hit || hit.ok !== true || hit.valid !== true) {
            continue;
        }
        if (await callGameAPI(page, ['is_target_cell', hit.x, hit.y, hit.z])) {
            continue;
        }
        if (await callGameAPI(page, ['is_cell_chiseled', hit.x, hit.y, hit.z])) {
            continue;
        }
        const point = await toPagePoint(page, candidate.nx, candidate.ny);
        if (point) {
            return { nx: candidate.nx, ny: candidate.ny, point, cell: { x: hit.x, y: hit.y, z: hit.z } };
        }
    }
    return null;
}


/** True only for the project whose device profile enables touch events. */
function touchRequired(testInfo) {
    return testInfo.project.name !== 'mobile-chromium';
}

test.describe('Mobile touch on the real puzzle', () => {
    let diagnostics;

    test.beforeEach(async ({ page }) => {
        diagnostics = attachBrowserDiagnostics(page);
        await page.goto('/');
        await waitForEngine(page);
    });

    test('a real touch tap on a voxel chisels it', async ({ page }, testInfo) => {
        test.skip(touchRequired(testInfo), 'dispatching touch events needs a touch-enabled context');
        await loadPuzzle(page);
        await assertCanvasRendered(page);
        expect(await callGameAPI(page, ['get_puzzle_state'])).toBe('IN_PROGRESS');

        const target = await findTappablePoint(page);
        expect(target, 'expected a screen point the game resolves to a tappable voxel').not.toBeNull();

        await page.touchscreen.tap(target.point.x, target.point.y);
        await page.waitForTimeout(500);
        expect(
            await callGameAPI(page, ['get_cell_state', target.cell.x, target.cell.y, target.cell.z]),
            'a genuine touch tap must chisel the voxel under the finger',
        ).toBe('destroyed');
        assertNoBrowserErrors(diagnostics);
    });

    test('a tap on an empty toolbar cell must not swallow the next tap', async ({ page }, testInfo) => {
        // Regression guard for the double-tap poisoning bug: a tap that resolves
        // to no voxel used to anchor the double-tap window, so the player's next
        // real chisel was silently discarded.
        test.skip(touchRequired(testInfo), 'dispatching touch events needs a touch-enabled context');
        await loadPuzzle(page);
        const rects = await callGameAPI(page, ['get_ui_rects']);
        expect(rects).toBeTruthy();
        const toolbar = rects.rects.find((entry) => entry.name === 'ResetViewButton');
        expect(toolbar, 'the puzzle toolbar must expose its controls').toBeTruthy();

        // Aim just past the right edge of the toolbar, in the empty stretch of
        // the bottom row that used to fall through to the puzzle's touch
        // Control and anchor the double-tap window.
        const visible = rects.visible;
        const nx = (toolbar.x + toolbar.w + 40) / visible.w;
        const ny = (toolbar.y + toolbar.h / 2) / visible.h;
        const emptyPoint = await toPagePoint(page, nx, ny);
        expect(emptyPoint).not.toBeNull();
        await page.touchscreen.tap(emptyPoint.x, emptyPoint.y);
        await page.waitForTimeout(120);

        // Now tap a real voxel immediately: this used to be eaten as a double tap.
        const target = await findTappablePoint(page);
        expect(target, 'expected a tappable voxel after the stray tap').not.toBeNull();
        await page.touchscreen.tap(target.point.x, target.point.y);
        await page.waitForTimeout(500);
        expect(
            await callGameAPI(page, ['get_cell_state', target.cell.x, target.cell.y, target.cell.z]),
            'a tap on an empty toolbar cell must not discard the next real tap',
        ).toBe('destroyed');
        assertNoBrowserErrors(diagnostics);
    });

    test('every gameplay control is reachable and non-overlapping in landscape', async ({ page }) => {
        await loadPuzzle(page);
        const layout = await callGameAPI(page, ['get_ui_rects']);
        expect(layout).toBeTruthy();
        const visible = layout.visible;
        const controls = layout.rects.filter((entry) => entry.visible);
        expect(controls.length, 'expected the puzzle toolbar to be on screen').toBeGreaterThanOrEqual(5);

        for (const control of controls) {
            expect(control.w, `${control.name} must have a real width`).toBeGreaterThan(0);
            expect(control.h, `${control.name} must meet the touch target height`).toBeGreaterThanOrEqual(40);
            expect(control.x, `${control.name} must start inside the viewport`).toBeGreaterThanOrEqual(visible.x - 1);
            expect(control.y, `${control.name} must start inside the viewport`).toBeGreaterThanOrEqual(visible.y - 1);
            expect(control.x + control.w, `${control.name} must end inside the viewport`).toBeLessThanOrEqual(visible.x + visible.w + 1);
            expect(control.y + control.h, `${control.name} must end inside the viewport`).toBeLessThanOrEqual(visible.y + visible.h + 1);
        }

        // No two controls may overlap, or one silently steals the other's taps.
        for (let i = 0; i < controls.length; i += 1) {
            for (let j = i + 1; j < controls.length; j += 1) {
                const a = controls[i];
                const b = controls[j];
                const overlaps = a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
                expect(overlaps, `${a.name} overlaps ${b.name}`).toBe(false);
            }
        }
        assertNoBrowserErrors(diagnostics);
    });

    test('the camera can never be pinched inside the puzzle and Reset recovers', async ({ page }) => {
        await loadPuzzle(page);
        const initial = await callGameAPI(page, ['get_camera_state']);
        expect(initial).toBeTruthy();
        expect(initial.target_distance).toBeGreaterThan(0);
        expect(
            initial.fitted_distance,
            'the puzzle camera must be auto-fitted on load, not left at a default',
        ).toBeGreaterThan(0);

        // Drive the zoom to its extreme through the real wheel/zoom input path.
        for (let i = 0; i < 40; i += 1) {
            await page.mouse.wheel(0, 240);
        }
        await page.waitForTimeout(600);
        const zoomed = await callGameAPI(page, ['get_camera_state']);
        expect(zoomed.target_distance).toBeGreaterThan(0);
        expect(
            zoomed.target_distance,
            'the camera must never be allowed inside the puzzle',
        ).toBeGreaterThanOrEqual(zoomed.min_distance - 0.001);

        // Reset View is the advertised recovery action and must actually recover.
        const layout = await callGameAPI(page, ['get_ui_rects']);
        const resetButton = layout.rects.find((entry) => entry.name === 'ResetViewButton');
        expect(resetButton, 'the puzzle must expose a Reset View control').toBeTruthy();
        expect(await callGameAPI(page, ['press_button', resetButton.path])).toBe(true);
        await page.waitForTimeout(1200);
        const reset = await callGameAPI(page, ['get_camera_state']);
        expect(
            Math.abs(reset.target_distance - initial.fitted_distance),
            'Reset View must restore the fitted distance, not just the orientation',
        ).toBeLessThan(0.5);
        assertNoBrowserErrors(diagnostics);
    });
});
