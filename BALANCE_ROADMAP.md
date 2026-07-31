# Automated Game Balance Roadmap

This document tracks the incremental balance improvements recommended by the headless telemetry system.

## Instructions for Agents
To run the automated flow and generate a new report, an agent should:
1. Run the headless telemetry runner: `godot --headless --script res://tools/telemetry_runner.gd`
2. Run the telemetry analyzer which patches files and updates this roadmap: `godot --headless --script res://tools/analyze_telemetry.gd`
3. Review the changes in `BALANCE_ROADMAP.md` and the automatically patched `.gd` files.
4. Use `git diff` to verify the automated parameter adjustments.
5. Commit the changes and open a pull request for the design team to review.

### Scheduled Automated Telemetry Runs
This repository is equipped with a GitHub Actions workflow (`.github/workflows/scheduled_telemetry.yml`) that periodically runs the telemetry suite headlessly.
If you are an agent responding to an automated issue triggered by this job, you should:
- Review the new sections appended to this file under **Telemetry Run Analytics**.
- Verify that any patched scripts (e.g., `Scripts/GameManager.gd` or `Scripts/VoxelGrid3D.gd`) correctly reflect the findings and do not break core logic.
- Commit any modified files directly or submit them as a PR depending on your directives.

## Telemetry Run Analytics: 2026-07-31 02:25:14

### MAIN_MENU
- **Time To Complete (TTC)**: 30.00 seconds
- **Actions Per Minute (APM)**: 28.00
- **Status**: Balanced. No immediate actions required.

---

### Historical Reports

## Telemetry Run Analytics: 2026-07-27 04:44:06

### LONE_WOLF_NARRATIVE
- **Time To Complete (TTC)**: 1.99 seconds
- **Actions Per Minute (APM)**: 30.22
- **Status**: Balanced. No immediate actions required.

### PICROSS_3D
- **Time To Complete (TTC)**: 3.03 seconds
- **Actions Per Minute (APM)**: 138.66
- **Status**: Balanced. No immediate actions required.

### MASQUERADE_PAINTING
- **Time To Complete (TTC)**: 3.02 seconds
- **Actions Per Minute (APM)**: 79.59
- **Status**: Balanced. No immediate actions required.

### LONE_WOLF_NARRATIVE
- **Time To Complete (TTC)**: 0.00 seconds
- **Actions Per Minute (APM)**: 100.00
- **Status**: Balanced. No immediate actions required.

---

### Historical Reports

## Telemetry Run Analytics: 2026-07-27 03:56:43

### LONE_WOLF_NARRATIVE
- **Time To Complete (TTC)**: 4.99 seconds
- **Actions Per Minute (APM)**: 24.04
- **Status**: Balanced. No immediate actions required.

### MASQUERADE_PAINTING
- **Time To Complete (TTC)**: 5.01 seconds
- **Actions Per Minute (APM)**: 47.91
- **Status**: Balanced. No immediate actions required.

### PICROSS_3D
- **Time To Complete (TTC)**: 5.01 seconds
- **Actions Per Minute (APM)**: 107.80
- **Status**: Balanced. No immediate actions required.

### ESCAPE_GAUNTLET
- **Time To Complete (TTC)**: 5.00 seconds
- **Actions Per Minute (APM)**: 287.86
- **Status**: Balanced. No immediate actions required.

---

### Historical Reports

## Telemetry Run Analytics: 2026-07-27 03:54:06

### LONE_WOLF_NARRATIVE
- **Time To Complete (TTC)**: 4.99 seconds
- **Actions Per Minute (APM)**: 24.04
- **Status**: Balanced. No immediate actions required.

### MASQUERADE_PAINTING
- **Time To Complete (TTC)**: 5.01 seconds
- **Actions Per Minute (APM)**: 47.91
- **Status**: Balanced. No immediate actions required.

### PICROSS_3D
- **Time To Complete (TTC)**: 5.01 seconds
- **Actions Per Minute (APM)**: 107.80
- **Status**: Balanced. No immediate actions required.

### ESCAPE_GAUNTLET
- **Time To Complete (TTC)**: 5.00 seconds
- **Actions Per Minute (APM)**: 287.87
- **Status**: Balanced. No immediate actions required.

---

### Historical Reports

## Telemetry Run Analytics: 2026-07-26 21:51:18

### LoneWolfNarrative
- **Time To Complete (TTC)**: 4.98 seconds
- **Actions Per Minute (APM)**: 24.07
- **Status**: Balanced. No immediate actions required.

### MasqueradePainting
- **Time To Complete (TTC)**: 5.01 seconds
- **Actions Per Minute (APM)**: 47.91
- **Status**: Balanced. No immediate actions required.

### Picross3D
- **Time To Complete (TTC)**: 5.01 seconds
- **Actions Per Minute (APM)**: 107.80
- **Status**: Balanced. No immediate actions required.

### EscapeGauntlet
- **Time To Complete (TTC)**: 5.00 seconds
- **Actions Per Minute (APM)**: 287.87
- **Status**: Balanced. No immediate actions required.

---

### Historical Reports

## Telemetry Run Analytics: 2026-07-26 20:59:34

### LoneWolfNarrative
- **Time To Complete (TTC)**: 4.99 seconds
- **Actions Per Minute (APM)**: 24.07
- **Status**: Balanced. No immediate actions required.

### MasqueradePainting
- **Time To Complete (TTC)**: 5.01 seconds
- **Actions Per Minute (APM)**: 47.91
- **Status**: Balanced. No immediate actions required.

### Picross3D
- **Time To Complete (TTC)**: 5.01 seconds
- **Actions Per Minute (APM)**: 107.80
- **Status**: Balanced. No immediate actions required.

### EscapeGauntlet
- **Time To Complete (TTC)**: 5.00 seconds
- **Actions Per Minute (APM)**: 287.86
- **Status**: Balanced. No immediate actions required.

---

### Historical Reports
