'use strict';

const fs = require('node:fs');
const path = require('node:path');

const pckPath = path.join(__dirname, '..', 'build', 'web', 'index.pck');
if (!fs.existsSync(pckPath)) {
  throw new Error(`Missing release artifact: ${pckPath}`);
}
const payload = fs.readFileSync(pckPath);
const text = payload.toString('utf8');
const forbidden = ['test_bridge', 'gameAPI', 'addons/gut'];
const found = forbidden.filter((needle) => text.includes(needle));
if (found.length > 0) {
  throw new Error(`Production Web PCK contains test-only content: ${found.join(', ')}`);
}
console.log(`[web-release] verified ${path.relative(process.cwd(), pckPath)} (${payload.length} bytes; no test bridge/API markers)`);
