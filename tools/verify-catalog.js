'use strict';

const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const CATALOG = path.join(ROOT, 'assets', 'puzzles', 'gauntlet_catalog.json');

function fail(message) {
    throw new Error(message);
}

function main() {
    if (!fs.existsSync(CATALOG)) fail(`Missing ${path.relative(ROOT, CATALOG)}`);
    const catalog = JSON.parse(fs.readFileSync(CATALOG, 'utf8'));
    if (!catalog || !Array.isArray(catalog.puzzles) || catalog.puzzles.length === 0) {
        fail('Catalog must contain a non-empty puzzles array');
    }
    const ids = new Set();
    for (const puzzle of catalog.puzzles) {
        const id = String(puzzle.id || '').trim();
        if (!id) fail('Catalog contains a puzzle without an id');
        if (ids.has(id)) fail(`Catalog contains duplicate id ${id}`);
        ids.add(id);
        const dims = puzzle.dims || puzzle.grid_size;
        if (!Array.isArray(dims) || dims.length !== 3 || dims.some((value) => !Number.isInteger(value) || value < 1 || value > 5)) {
            fail(`${id} has invalid dimensions`);
        }
        if (!Array.isArray(puzzle.target_voxels) || puzzle.target_voxels.length === 0) {
            fail(`${id} has no target voxels`);
        }
        for (const coordinate of puzzle.target_voxels) {
            if (!Array.isArray(coordinate) || coordinate.length !== 3 || coordinate.some((value, index) => !Number.isInteger(value) || value < 0 || value >= dims[index])) {
                fail(`${id} has an out-of-bounds target coordinate`);
            }
        }
        if (!puzzle.clues || typeof puzzle.clues !== 'object') fail(`${id} has no clues`);
    }
    console.log(`[catalog] verified ${catalog.puzzles.length} entries; unique ids and bounded target coordinates`);
}

main();
