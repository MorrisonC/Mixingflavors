'use strict';

const { defineConfig, devices } = require('@playwright/test');

const requestedPort = process.env.PLAYWRIGHT_PORT || process.env.PORT || '8080';
const port = Number(requestedPort);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`PLAYWRIGHT_PORT/PORT must be an integer between 1 and 65535; received ${requestedPort}`);
}

const baseURL = `http://127.0.0.1:${port}`;

module.exports = defineConfig({
    testDir: './tests/playwright',
    // Must exceed ENGINE_READY_TIMEOUT in tests/playwright/test-utils.js so a
    // slow-but-correct wasm boot is not reported as a test failure.
    timeout: 180000,
    expect: {
        timeout: 15000,
    },
    fullyParallel: false,
    forbidOnly: Boolean(process.env.CI),
    retries: 0,
    workers: 1,
    reporter: [
        ['list'],
        ['html', { open: 'never' }],
    ],
    use: {
        baseURL,
        headless: true,
        actionTimeout: 10000,
        navigationTimeout: 30000,
        trace: 'retain-on-failure',
    },
    projects: [
        {
            name: 'chromium',
            testIgnore: /mobile\.spec\.js$/,
            use: {
                ...devices['Desktop Chrome'],
                browserName: 'chromium',
            },
        },
        {
            name: 'mobile-chromium',
            testMatch: /mobile(_touch)?\.spec\.js$/,
            use: {
                ...devices['Pixel 5'],
                browserName: 'chromium',
                viewport: { width: 851, height: 393 },
                screen: { width: 851, height: 393 },
            },
        },
    ],
    // The build is deliberately part of the server command.  With
    // reuseExistingServer disabled, neither a stale local server nor a stale
    // build/web directory can be used by an E2E run.
    webServer: {
        command: 'npm run build:web && node server.js',
        url: baseURL,
        timeout: 600000,
        reuseExistingServer: false,
        env: {
            ...process.env,
            PORT: String(port),
            WEB_TEST_BUILD: '1',
        },
    },
});
