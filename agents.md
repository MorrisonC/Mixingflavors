# Godot Project Guide

## Project

Mixing Flavors: Voxel Gauntlet is a deterministic 3D Picross time-attack game built with Godot 4.7.x. The shipping vertical slice is landscape-first and targets Web and Android.

## Required tests

Run the GUT suite headlessly before declaring a change complete:

```powershell
godot --headless --rendering-driver opengl3 -s addons/gut/gut_cmdln.gd -gdir=res://test/unit/ -gexit
```

Run the fresh Web export and browser suite with:

```powershell
$env:GODOT_BIN='<path-to-godot-4.7.1-console>'
npm run build:web
$env:PLAYWRIGHT_PORT='8082'
npm test
```

## Architecture

- `scripts/GameManager.gd` routes modes and payloads.
- `scripts/PuzzleManager.gd` loads the fast runtime catalog and selects deterministic puzzles.
- `scripts/GauntletManager.gd` owns timer, depth, streak, score, and banking rules.
- `scripts/SaveManager.gd` is the authoritative profile store.
- `scripts/GachaService.gd` is a pure deterministic gacha domain service.
- `scripts/GridManager.gd` owns voxel state, clues, input, undo, and MultiMesh rendering.
- `scripts/EscapeGauntlet.gd` presents the gauntlet and binds the service to the puzzle scene.

## Rules

- Never hardcode puzzle solutions in gameplay code; puzzle data belongs under `assets/puzzles/` or `data/puzzles/`.
- Never bypass puzzle validation for player-facing content.
- Keep generated `build/`, `test-results/`, `playwright-report/`, and `node_modules/` out of version control.
- Use MultiMesh batching for voxel rendering and avoid allocations in frame loops.
- Keep browser tests serial because the Godot JavaScript bridge uses a shared callback.
- Do not remove a failing test to hide a regression; update the contract or implementation deliberately.
