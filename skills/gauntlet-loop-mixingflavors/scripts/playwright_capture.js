// Minimal Playwright capture helper for the gauntlet loop's builder step.
// Usage: node playwright_capture.js --url <url> --out <dir>
//
// Uses Playwright, which is already a dependency of this repo
// (playwright.config.js, tests/playwright/). Takes a full-page
// screenshot plus a short delay to let the Godot web export finish
// booting before capturing -- WebGL/canvas games are slower to first
// paint than a typical page.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {};
  for (let i = 0; i < args.length; i += 2) {
    out[args[i].replace(/^--/, '')] = args[i + 1];
  }
  return out;
}

(async () => {
  const { url, out } = parseArgs();
  if (!url || !out) {
    console.error('Usage: node playwright_capture.js --url <url> --out <dir>');
    process.exit(1);
  }
  fs.mkdirSync(out, { recursive: true });

  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });

  console.log(`[playwright_capture] Loading ${url}`);
  await page.goto(url, { waitUntil: 'networkidle' });

  // Godot web exports boot into a canvas after an initial loading
  // screen -- give it a beat before capturing so the shot isn't just
  // the loading bar.
  await page.waitForTimeout(4000);

  const outPath = path.join(out, 'capture.png');
  await page.screenshot({ path: outPath, fullPage: false });
  console.log(`[playwright_capture] Wrote ${outPath}`);

  await browser.close();
})().catch((err) => {
  console.error('[playwright_capture] FAILED:', err);
  process.exit(1);
});
