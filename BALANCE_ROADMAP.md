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
