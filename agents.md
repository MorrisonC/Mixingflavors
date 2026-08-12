# Godot Engine Project Context & Developer Guide

## Project Overview
This project is a 3D Picross (Nonogram) logic puzzle game built with Godot 4.x. Players deduce which voxels (cubes) within a 3D grid must be kept (marked) or removed (chiseled) based on numeric hints displayed along the rows, columns, and depth layers across 3 spatial axes ($X, Y, Z$) instead of the traditional 2D Picross grid.

---

## How to Run Automated Tests
Jules MUST run tests in headless mode inside the VM:
`godot --headless --rendering-driver opengl3 -s addons/gut/gut_cmdln.gd -gdir=res://test/unit/ -gexit`

---

## Core Architecture
- **Grid Data Representation**: The 3D grid is stored logically using `Vector3i` keys mapping to state dictionaries (`voxel_states: Dictionary`) representing states such as `is_chiseled`, `is_marked`, `is_painted`, and `is_hidden_by_slice`. Solution data is maintained separately in `target_solution: Dictionary[Vector3i, bool]`.
- **Hint Calculation & Validation**: Row/column/layer hint numbers are generated via `_calculate_clue()` in `GridManager.gd` and solved/validated using `VoxelLogicSolver.gd` and `SolvabilityValidator.gd`. Simple counts correspond to contiguous blocks (`3`), parenthesized counts indicate broken blocks (`(3)`), and bracketed counts indicate multi-segment groups (`[3]`).
- **Puzzle Definition & Storage**: Puzzles are registered and loaded via `PuzzleRegistry.gd` and stored as JSON structures containing dimensions (`dims`), target voxel coordinates (`target_voxels`), and optional pre-calculated `hints` or `cells`.
- **Logic & Rendering Separation**: Game logic resides in `GridManager.gd` and helper solver classes. Rendering is decoupled using `MultiMeshInstance3D` batching for static grid blocks and individual `VoxelBlock` nodes for exposed interactive faces and 3D hint labels (`Label3D` / `Sprite3D`).

---

## Scene Structure Conventions
- **Scene Location**: All `.tscn` scene files reside in `res://scenes/` (e.g., `GridManager.tscn`, `MainMenu.tscn`, `Block.tscn`, `EscapeGauntlet.tscn`).
- **Script Location**: All `.gd` GDScript files reside in `res://scripts/` (e.g., `GridManager.gd`, `Block.gd`, `GameManager.gd`).
- **Node Hierarchy**:
  - `GridManager` (Node3D root)
    - `CameraPivot` (CameraPivotController for 3D orbit)
    - `MultiMeshInstances` (`multimesh_unbroken`, `multimesh_marked`, `multimesh_outline`)
    - `CanvasLayer` (UI controls, slice sliders, mode toggles, touch overlay)

---

## Camera & Interaction Conventions
- **3D Camera Orbit**: Handled by `CameraPivotController.gd`, allowing smooth rotational panning and distance zooming around the center of the 3D grid bounds.
- **Raycast Interaction**: Voxel selection and raycasting are managed in `MobileTouchControls.gd` and `GridManager.gd`. Inputs trigger raycasts from the camera to detect voxel face hits.
- **Input Modes**:
  - `EditMode.DESTROY`: Chisels/breaks targeted voxels.
  - `EditMode.MARK`: Toggles green/marked protection flag on voxels.
  - `EditMode.PAINT`: Colors marked voxels.
  - `Slice Sliders`: Hides outer grid slices along X, Y, or Z axes to expose internal voxels.

---

## State & Save System
- **Persistence**: Game progress, high scores, trophy unlocks, and options are managed by `SaveSystem.gd` and saved as JSON to `user://save_data.json`.
- **Move History & Undo**: `GridManager.gd` tracks move histories (`move_history` stack), enabling step-by-step undo operations via `undo_last_move()`.
- **Run Tracking**: Meta-progression, boss damage, and run statistics are aggregated across floors by `RunHistoryManager.gd`.

---

## Testing Conventions
- **Test Directory**: All GUT unit tests MUST be located in `res://test/unit/` (e.g., `test_grid_manager.gd`, `test_picross_rules.gd`, `test_time_bomb.gd`).
- **Test Naming**: Test files must follow the pattern `test_<feature_name>.gd` and inherit from `GutTest`.
- **What Must Be Tested**:
  - Core grid logic, state transitions, and move validation.
  - Hint formatting and clue calculation logic.
  - Puzzle solvability via `SolvabilityValidator.gd`.
  - Game rules, HP/mistake counts, and win/loss condition checks.
- **What Does Not Need Tests**: Pure visual particle effects, audio triggers, UI animations, and shaders.
- **SceneTree Management**: In GUT test scripts, instantiate scenes dynamically and register them using `add_child_autoqfree()` to ensure proper memory cleanup after test execution.

---

## Style & Code Conventions
- **GDScript Style Guide**: Strict adherence to standard GDScript formatting (4-space indentation, snake_case methods/variables, PascalCase classes).
- **Static Typing**: Explicit static typing (`var x: int = 0`, `func foo() -> void:`) is REQUIRED on all new scripts and modified functions.
- **Class Declarations**: Explicit `class_name` header declarations required for domain classes (e.g., `class_name VoxelBlock`, `class_name GridManager`).
- **Signal Conventions**: Use descriptive past-tense signal names (e.g., `signal block_destroyed`, `signal voxel_marked`, `signal puzzle_solved`).
- **Autoload Singletons**: Global management is strictly delegated to registered autoloads (`GameManager`, `SaveSystem`, `AudioManager`, `TelemetryService`).

---

## Performance Constraints
- **Voxel Mesh Batching**: Grid blocks MUST be rendered via `MultiMeshInstance3D` to minimize draw calls across large voxel grids.
- **Grid Limits**: Puzzle grid sizes should target a maximum of $5 \times 5 \times 5$ (or 125 active voxels) for mobile performance.
- **Allocation Rules**: Avoid allocating new materials or instantiating mesh nodes inside per-frame `_process()` or `_physics_process()` loops.

---

## Do-Nots & Guardrails
- **NEVER hardcode puzzle solutions** directly in gameplay code.
- **NEVER bypass puzzle validation** or solvability checks.
- **NEVER submit changes if the GUT test suite fails**.
- **NEVER hardcode cross-scene node paths**; keep scenes decoupled using signals.
- **NEVER delete failing assertions or unit tests** to mask bugs.

---

## PR & Commit Conventions
- **Commit Format**: Follow Conventional Commits format:
  - `feat:` for new gameplay features or mechanics.
  - `fix:` for bug fixes.
  - `refactor:` for code or rendering refactoring without behavioral changes.
  - `test:` for adding or updating test cases.
  - `docs:` for documentation updates.
- **PR Requirements**: Include a summary of changes, rationale, list of modified files, and verification steps (e.g., test suite results).

## Playwright Screenshots
When capturing visual evidence for PRs using Playwright (e.g., visual regression snapshots or manual screenshots), save them to `tests/playwright/screenshots/`.
