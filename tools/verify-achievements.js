'use strict';

// Guards the optional Google Play Games adapter boundary.
//
// The local `AchievementService` is authoritative for offline play. This manifest
// only maps local achievement ids onto Play Console resources, so it must never
// claim resources (console ids, icon files) that do not exist yet.

const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const MANIFEST = path.join(ROOT, 'data', 'achievements', 'google_play_manifest.json');
const SERVICE = path.join(ROOT, 'scripts', 'AchievementService.gd');

function fail(message) {
    throw new Error(message);
}

function readLocalAchievementIds() {
    if (!fs.existsSync(SERVICE)) fail(`Missing ${path.relative(ROOT, SERVICE)}`);
    const source = fs.readFileSync(SERVICE, 'utf8');
    const ids = new Set();
    for (const match of source.matchAll(/"id":\s*"([a-z0-9_]+)"/g)) {
        ids.add(match[1]);
    }
    if (ids.size === 0) fail('No achievement ids parsed from AchievementService.gd');
    return ids;
}

function main() {
    if (!fs.existsSync(MANIFEST)) fail(`Missing ${path.relative(ROOT, MANIFEST)}`);
    const manifest = JSON.parse(fs.readFileSync(MANIFEST, 'utf8'));
    if (manifest.platform !== 'google_play_games_v2') fail('Manifest platform must be google_play_games_v2');
    if (!Array.isArray(manifest.achievements) || manifest.achievements.length === 0) {
        fail('Manifest must contain a non-empty achievements array');
    }

    const localIds = readLocalAchievementIds();
    const seen = new Set();
    let pendingConsoleIds = 0;

    for (const entry of manifest.achievements) {
        const id = String(entry.local_id || '').trim();
        if (!id) fail('Manifest contains an achievement without a local_id');
        if (seen.has(id)) fail(`Manifest contains duplicate local_id ${id}`);
        seen.add(id);
        if (!localIds.has(id)) fail(`Manifest local_id ${id} has no AchievementService definition`);

        const consoleId = String(entry.play_games_id || '').trim();
        if (consoleId === '') {
            pendingConsoleIds += 1;
        } else {
            if (!/^[A-Za-z0-9_-]{3,}$/.test(consoleId)) {
                fail(`${id} has a malformed play_games_id: ${consoleId}`);
            }
            if (consoleId.toLowerCase() === id) {
                fail(`${id} reuses the local id as a Console placeholder; fill the real id or leave it blank`);
            }
        }

        const icon = String(entry.icon || '').trim();
        if (icon) {
            if (!icon.startsWith('res://') && !icon.startsWith('assets/') && !icon.startsWith('user://')) {
                fail(`${id} has an icon path outside the project: ${icon}`);
            }
            const onDisk = icon.startsWith('res://') ? icon.slice('res://'.length) : icon;
            if (!fs.existsSync(path.join(ROOT, onDisk))) {
                fail(`${id} references a missing icon file: ${icon}`);
            }
        }
    }

    for (const id of localIds) {
        if (!seen.has(id)) fail(`AchievementService defines ${id} but the manifest omits it`);
    }

    const pendingIcons = manifest.achievements.filter((entry) => !String(entry.icon || '').trim()).length;
    console.log(
        `[achievements] verified ${manifest.achievements.length} entries; ` +
        `${pendingConsoleIds} awaiting Play Console ids, ${pendingIcons} awaiting icons`
    );
}

main();
