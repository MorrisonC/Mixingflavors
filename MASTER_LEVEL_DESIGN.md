# Master Level Design & Architecture Document

This document serves as our single source of truth for level maps, puzzle logic, gameplay archetypes (GameModes), and navigation flow. It details the hybrid mechanics that drive progression.

---

## 1. World & Navigation Flow Architecture

### Global Progression Graph
*Visualizes how the distinct GameModes connect and flow into one another.*

```mermaid
graph TD
    Start[LoneWolfNarrative: Introduction] --> L1[DetectiveCrimeScene: The Investigation]
    L1 --> Hub[Central Hub: Narrative Crossroad]

    Hub --> L2[MasqueradePainting: The Canvas]
    Hub --> L3[Picross3D: Voxel Puzzle]

    L2 -.->|Canvas Solved| Sub1[EscapeGauntlet: The Chase]
    L3 -.->|Structure Restored| Sub2[TimeShiftPalimpsest: The Overlay]

    Sub1 --> Boss1[Climax: Integration Challenge]
    Sub2 --> Boss2[Climax: Temporal Paradox]
```

### RPG Stats as Cross-Mechanic Modifiers
*How the core RPG stats defined in GameManager.gd interact with different game modes.*

| Stat Name | Relevant Mode(s) | Effect / Modifier |
| :--- | :--- | :--- |
| **Perception** | `MasqueradePainting` | If `perception_level > 1`, hidden anchors are revealed on the 2D canvas, making connections easier. |
| **Health & Endurance** | `Picross3D` | If `health < 50` or `endurance < 50`, the 3D voxel states become corrupted (turning red), increasing puzzle difficulty. |
| **Alchemy Discipline** | `Picross3D` | If `alchemy_discipline > 1`, the player can apply custom colors/materials to voxels, solving advanced puzzle constraints. |
| **Lore Discipline** | `LoneWolfNarrative`, `DetectiveCrimeScene` | Unlocks additional dialogue options and contextual clues. |

---

## 2. Gameplay Archetypes (GameModes)

### Mode Overview
The application currently integrates multiple distinct structural archetypes, driven by `GameManager.gd`:

1. **`LoneWolfNarrative` (Gamebook Narrative)**: Text/Node-based narrative progression.
2. **`MasqueradePainting` (2D Painting)**: Driven by `PaintingCanvas2D.gd`. Players draw lines connecting hidden anchors. Success relies on deduction or high Perception.
3. **`Picross3D` (3D Voxel Puzzles)**: Driven by `VoxelGrid3D.gd`. Players chisel away incorrect voxels and use Alchemy to color them. Solving this passes templates to the 2D canvas.
4. **`DetectiveCrimeScene`**: Non-linear 3D/2D exploration for uncovering clues.
5. **`EscapeGauntlet`**: Time-pressured Voxel puzzles under extreme tension.
6. **`TimeShiftPalimpsest`**: 2D past/present overlays requiring temporal deduction.

---

## 3. Core Gameplay Loops & Integration

### The Cross-Mechanic Puzzle Matrix

| Interaction | Source Mode | Target Mode | Required Stat/Condition | Result / Reward |
| :--- | :--- | :--- | :--- | :--- |
| **Solve Voxel Template** | `Picross3D` | `MasqueradePainting` | `alchemy_discipline > 1` | Correctly chiseling and coloring a 3D structure registers new hidden anchors on the 2D painting canvas. |
| **Reveal Canvas Anchors** | `LoneWolfNarrative` | `MasqueradePainting` | `perception_level > 1` | Making the right narrative choices boosts Perception, revealing hidden dynamic anchors (e.g., pendulums) on the canvas. |
| **Survive Corruption** | `EscapeGauntlet` | `Picross3D` | `health > 50`, `endurance > 50` | Maintaining high health/endurance prevents voxels from corrupting during time-pressured chiseling sequences. |

### Kishōtenketsu Design Sequence (Example: 3D to 2D Pipeline)
- **Ki (Introduction):** Player starts in `LoneWolfNarrative`, learning about a hidden sigil.
- **Shō (Development):** The game shifts to `Picross3D`. The player chisels a 3D voxel block based on clues.
- **Ten (Twist/Complication):** The player's health drops, corrupting the voxels. They must use their `Alchemy` stat to recolor specific blocks to stabilize the structure.
- **Ketsu (Conclusion):** The stabilized 3D voxel structure is passed to the `MasqueradePainting` mode as a set of hidden 2D anchors. The player connects these points to unlock the next narrative chapter.

---

## 4. Expansion Roadmap & Status

*Tracking the implementation of the structural archetypes.*

| GameMode ID | Description | Status | Core Script Dependency |
| :--- | :--- | :--- | :--- |
| `LoneWolfNarrative` | Node-based text narrative | `[Playtested]` | `GameManager.gd` |
| `MasqueradePainting`| 2D anchor connection canvas | `[Playtested]` | `PaintingCanvas2D.gd` |
| `Picross3D` | 3D chiseling and coloring | `[Playtested]` | `VoxelGrid3D.gd` |
| `DetectiveCrimeScene`| Non-linear exploration | `[Draft]` | TBD |
| `EscapeGauntlet` | Timed pressure sequences | `[Blockout]` | TBD |
| `TimeShiftPalimpsest`| Temporal 2D overlay puzzles | `[Draft]` | TBD |
