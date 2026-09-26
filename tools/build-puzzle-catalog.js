'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const PUZZLE_ROOT = path.join(ROOT, 'assets', 'puzzles');
const OUTPUT = path.join(PUZZLE_ROOT, 'gauntlet_catalog.json');
const TIERS = ['easy', 'medium', 'hard'];
const THEME_ORDER = [
    'animals', 'nature', 'mythical', 'fantasy', 'scifi', 'cyberpunk',
    'treasure', 'alchemy', 'arcade', 'vehicles',
];

function readJson(filePath) {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function dimensionsForTier(tier) {
    if (tier === 'easy') return [3, 3, 3];
    if (tier === 'medium') return [4, 4, 4];
    return [5, 5, 5];
}

function dimensionsMatch(puzzle, preferred) {
    const dimensions = puzzle.dims || puzzle.grid_size;
    return Array.isArray(dimensions)
        && dimensions.length === 3
        && dimensions.every((value, index) => Number(value) === preferred[index]);
}

function canonicalize(puzzle) {
    const dimensions = puzzle.dims || puzzle.grid_size;
    return {
        id: String(puzzle.id),
        name: String(puzzle.name || puzzle.id),
        theme: String(puzzle.theme || 'unknown'),
        difficulty_tier: String(puzzle.difficulty_tier || 'medium'),
        difficulty_score: Number(puzzle.difficulty_score || 0),
        par_time_seconds: Number(puzzle.par_time_seconds || 120),
        dims: dimensions.map(Number),
        grid_size: dimensions.map(Number),
        voxel_count: Array.isArray(puzzle.target_voxels) ? puzzle.target_voxels.length : 0,
        target_voxels: puzzle.target_voxels,
        clues: puzzle.clues || puzzle.hints || {},
        matching_asset_id: puzzle.matching_asset_id || '',
        solvable: true,
        runtime_validated: true,
    };
}

function choosePuzzle(puzzles, tier, preferred) {
    const candidates = puzzles.filter((puzzle) => (
        puzzle
        && Array.isArray(puzzle.target_voxels)
        && puzzle.target_voxels.length > 0
        && (puzzle.dims || puzzle.grid_size)?.length === 3
        && (puzzle.dims || puzzle.grid_size).every((value) => Number(value) <= 5)
        && String(puzzle.difficulty_tier || '').toLowerCase() === tier
    ));
    return candidates.find((puzzle) => dimensionsMatch(puzzle, preferred)) || candidates[0] || null;
}

function main() {
    const selected = [];
    const usedIds = new Set();
    for (const theme of THEME_ORDER) {
        const sourcePath = path.join(PUZZLE_ROOT, `${theme}_puzzles.json`);
        if (!fs.existsSync(sourcePath)) continue;
        const source = readJson(sourcePath);
        const puzzles = Array.isArray(source.puzzles) ? source.puzzles : [];
        for (const tier of TIERS) {
            const candidate = choosePuzzle(puzzles, tier, dimensionsForTier(tier));
            if (!candidate || usedIds.has(String(candidate.id))) continue;
            usedIds.add(String(candidate.id));
            selected.push(canonicalize(candidate));
        }
    }

    if (selected.length < TIERS.length) {
        throw new Error(`Expected at least ${TIERS.length} catalog puzzles, found ${selected.length}`);
    }

    const sourceManifestPath = path.join(PUZZLE_ROOT, 'puzzle_manifest.json');
    const sourceManifest = fs.existsSync(sourceManifestPath) ? readJson(sourceManifestPath) : {};
    const sourceTotal = Number.isInteger(sourceManifest.total_puzzles)
        ? sourceManifest.total_puzzles
        : selected.length;
    const output = {
        schema_version: 2,
        source_manifest: 'puzzle_manifest.json',
        source_total: sourceTotal,
        runtime_selection: 'deterministic-by-run-seed-and-depth',
        // This is a content fingerprint, not a substitute for strict runtime
        // validation. GridManager/PuzzleManager still validate every clue.
        puzzles: selected,
    };
    const serialized = JSON.stringify(output, null, 2);
    output.catalog_fingerprint = crypto.createHash('sha256').update(serialized).digest('hex');
    fs.writeFileSync(OUTPUT, `${JSON.stringify(output, null, 2)}\n`, 'utf8');
    console.log(`Wrote ${selected.length} validated catalog candidates to ${path.relative(ROOT, OUTPUT)}`);
}

main();
