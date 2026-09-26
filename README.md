# Mixing Flavors: Voxel Gauntlet

A deterministic 3D Picross time-attack game built with Godot 4.7.x. The shipping vertical slice includes:

- A validated, deterministic runtime puzzle catalog
- 3D chisel/mark interaction with X/Y/Z clues and slice controls
- A 120-second endless gauntlet with deterministic difficulty scaling
- Gacha rolls with rarity rates, pity counters, and duplicate shard conversion
- A persistent shard/inventory/completion profile
- A lightweight voxel archive screen
- Offline-first local achievements with an optional Google Play Games adapter boundary
- Seeded replay/share actions and recoverable local saves
- Web and Android export presets

## Requirements

- Godot 4.7.1 or 4.7.2
- Node.js 20+

## Run the web export

```powershell
npm ci
npm run build:web
npm run serve:web
```

Open `http://127.0.0.1:8080/` (set `PORT` to use another port).

## Tests

Headless GUT:

```powershell
godot --headless --rendering-driver opengl3 -s addons/gut/gut_cmdln.gd -gdir=res://test/unit/ -gexit
```

Web export and Playwright:

```powershell
$env:PLAYWRIGHT_PORT='8082'
npm test
```

The Playwright configuration builds a fresh export and serves it on an isolated port. Generated `build/`, `test-results/`, and `playwright-report/` files are not source-controlled.

Content gates that also run inside `npm run build:web`:

```powershell
npm run verify:catalog
npm run verify:achievements
```

`verify:catalog` bounds the runtime puzzle catalog; `verify:achievements` fails if the Google Play manifest drifts from the local achievement definitions, points at a missing icon, or reuses a local id as a Console placeholder.

## Content

`assets/puzzles/gauntlet_catalog.json` is the small, fast runtime catalog generated from the larger deterministic theme library. Regenerate it with:

```powershell
npm run build:puzzles
```

The full source corpus remains under `assets/puzzles/` for future compendium shards and archive content.

## Polish and release notes

- `docs/polish_research.md` records the camera, audio, mobile, asset, and replay decisions.
- `docs/google_play_achievements.md` describes the offline-first achievement and PGS v2 handoff.
- `docs/android_release.md` tracks the API-36 AAB, signing, device, and 16 KB page-size release gates.
- `todo.md` is the active product and release backlog.
