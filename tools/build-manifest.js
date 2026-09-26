'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const OUTPUT = path.join(ROOT, 'build_manifest.json');
const ROOTS = ['scripts', 'scenes', 'assets/puzzles', 'data/puzzles', 'test/unit', 'tests/playwright'];
const FILES = ['project.godot', 'export_presets.cfg', 'package.json', 'playwright.config.js'];

function walk(relativePath, output) {
    const absolutePath = path.join(ROOT, relativePath);
    if (!fs.existsSync(absolutePath)) return;
    const stat = fs.statSync(absolutePath);
    if (stat.isDirectory()) {
        for (const entry of fs.readdirSync(absolutePath).sort()) {
            walk(path.join(relativePath, entry), output);
        }
        return;
    }
    if (!stat.isFile() || relativePath.includes('.import')) return;
    const bytes = fs.readFileSync(absolutePath);
    output[relativePath.replaceAll('\\', '/')] = crypto.createHash('sha256').update(bytes).digest('hex');
}

function main() {
    const files = {};
    for (const root of ROOTS) walk(root, files);
    for (const file of FILES) walk(file, files);
    const manifest = {
        schema_version: 1,
        generated_by: 'tools/build-manifest.js',
        catalog_version: 1,
        files: Object.fromEntries(Object.entries(files).sort(([a], [b]) => a.localeCompare(b))),
    };
    fs.writeFileSync(OUTPUT, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
    console.log(`Wrote ${Object.keys(files).length} file hashes to ${path.relative(ROOT, OUTPUT)}`);
}

main();
