'use strict';

const { expect } = require('@playwright/test');

// The web build streams and compiles a ~39 MB index.wasm before gameAPI is
// injected. On an idle machine that takes 10-35s, but on a loaded CI or dev
// machine it can legitimately exceed a minute. This is a harness budget, not a
// product assertion: a genuine boot failure still fails fast and loudly.
const ENGINE_READY_TIMEOUT = 120000;
const API_RESULT_TIMEOUT = 15000;

function attachBrowserDiagnostics(page) {
    const diagnostics = {
        consoleErrors: [],
        pageErrors: [],
        warnings: [],
    };

    page.on('console', (message) => {
        const text = message.text();
        if (message.type() === 'error') {
            diagnostics.consoleErrors.push(text);
        } else if (message.type() === 'warning' || /WebGL|shader/i.test(text)) {
            diagnostics.warnings.push(text);
        }
    });
    page.on('pageerror', (error) => {
        diagnostics.pageErrors.push(error.message);
    });

    return diagnostics;
}

async function waitForEngine(page) {
    await page.waitForFunction(
        () => typeof window.gameAPI !== 'undefined' && window.gameAPI !== null,
        undefined,
        { timeout: ENGINE_READY_TIMEOUT },
    );
    await page.waitForTimeout(2000);
}

async function callGameAPI(page, args) {
    await page.evaluate(() => {
        window.__godot_promise = new Promise((resolve) => {
            window.__godot_resolve = resolve;
        });
    });

    await page.evaluate((apiArgs) => {
        if (typeof window.gameAPI === 'undefined' || window.gameAPI === null) {
            throw new Error('Godot test bridge is not available');
        }
        window.gameAPI(apiArgs);
    }, args);

    return page.evaluate((timeoutMs) => {
        return Promise.race([
            window.__godot_promise,
            new Promise((_, reject) => {
                window.setTimeout(() => reject(new Error(`Timed out waiting for Godot API result after ${timeoutMs}ms`)), timeoutMs);
            }),
        ]);
    }, API_RESULT_TIMEOUT);
}

async function canvasRenderStats(page) {
    return page.evaluate(() => {
        const canvas = document.getElementById('canvas');
        if (!canvas) {
            return { error: 'canvas element is missing' };
        }
        if (!canvas.width || !canvas.height) {
            return { error: `canvas has invalid size ${canvas.width}x${canvas.height}` };
        }

        const probe = document.createElement('canvas');
        probe.width = Math.min(160, canvas.width);
        probe.height = Math.min(160, canvas.height);
        const context = probe.getContext('2d', { willReadFrequently: true });
        if (!context) {
            return { error: '2D probe context is unavailable' };
        }

        try {
            context.clearRect(0, 0, probe.width, probe.height);
            context.drawImage(canvas, 0, 0, probe.width, probe.height);
            const pixels = context.getImageData(0, 0, probe.width, probe.height).data;
            let visiblePixels = 0;
            let nonBlackPixels = 0;
            let nonWhitePixels = 0;
            let colorPixels = 0;

            for (let index = 0; index < pixels.length; index += 4) {
                const red = pixels[index];
                const green = pixels[index + 1];
                const blue = pixels[index + 2];
                const alpha = pixels[index + 3];
                if (alpha === 0) {
                    continue;
                }
                visiblePixels += 1;
                if (red + green + blue > 24) {
                    nonBlackPixels += 1;
                }
                if (red < 245 || green < 245 || blue < 245) {
                    nonWhitePixels += 1;
                }
                if (Math.max(red, green, blue) - Math.min(red, green, blue) > 12) {
                    colorPixels += 1;
                }
            }

            const totalPixels = probe.width * probe.height;
            return {
                width: canvas.width,
                height: canvas.height,
                totalPixels,
                visiblePixels,
                nonBlackPixels,
                nonWhitePixels,
                colorPixels,
            };
        } catch (error) {
            return { error: error instanceof Error ? error.message : String(error) };
        }
    });
}

async function assertCanvasRendered(page) {
    let stats = null;
    for (let attempt = 0; attempt < 60; attempt += 1) {
        stats = await canvasRenderStats(page);
        const hasPixels = stats && !stats.error
            && stats.visiblePixels > stats.totalPixels * 0.5
            && stats.nonBlackPixels > stats.totalPixels * 0.01
            && stats.nonWhitePixels + stats.colorPixels > stats.totalPixels * 0.01;
        if (hasPixels) {
            return stats;
        }
        await page.waitForTimeout(250);
    }

    const finalStats = stats || {
        totalPixels: 0,
        visiblePixels: 0,
        nonBlackPixels: 0,
        nonWhitePixels: 0,
        colorPixels: 0,
    };
    expect(finalStats.error, `canvas probe failed: ${finalStats.error || 'unknown error'}`).toBeUndefined();
    expect(finalStats.visiblePixels, 'canvas should contain visible pixels').toBeGreaterThan(finalStats.totalPixels * 0.5);
    expect(finalStats.nonBlackPixels, 'canvas should not be uniformly black').toBeGreaterThan(finalStats.totalPixels * 0.01);
    expect(
        finalStats.nonWhitePixels + finalStats.colorPixels,
        'canvas should contain non-white detail or color',
    ).toBeGreaterThan(finalStats.totalPixels * 0.01);
    return finalStats;
}

function assertNoBrowserErrors(diagnostics) {
    if (!diagnostics) {
        return;
    }
    expect(
        diagnostics.pageErrors,
        `browser page errors:\n${diagnostics.pageErrors.join('\n')}`,
    ).toEqual([]);
    expect(
        diagnostics.consoleErrors,
        `browser console errors:\n${diagnostics.consoleErrors.join('\n')}`,
    ).toEqual([]);
}

function assertNoUnexpectedWebGlWarnings(diagnostics) {
    const unexpected = diagnostics.warnings.filter((warning) => {
        return !warning.includes('GL Driver Message') && !warning.includes('OpenGL API OpenGL ES');
    });
    expect(
        unexpected,
        `unexpected browser warnings:\n${unexpected.join('\n')}`,
    ).toEqual([]);
}

module.exports = {
    API_RESULT_TIMEOUT,
    assertCanvasRendered,
    assertNoBrowserErrors,
    assertNoUnexpectedWebGlWarnings,
    attachBrowserDiagnostics,
    callGameAPI,
    canvasRenderStats,
    waitForEngine,
};
