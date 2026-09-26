# Polish and mobile research notes

**Review date:** 2026-09-25  
**Audience:** Godot 4.7, landscape-first Web/Android vertical slice

## Decisions for this iteration

- **Victory is a data surface, not decoration.** Result initialization is
  deferred until `@onready` controls exist. The card renders level, elapsed
  time, score, stars, seed, best context, and replay actions. Gauntlet cards
  use a non-mutating `GauntletManager.preview_clear()` projection so the score
  shown before Continue is the score committed afterward.
- **The camera starts at a readable three-quarter angle** (`-34°` yaw,
  `24°` pitch), uses normalized orbit deltas, clamps zoom, refits on aspect
  changes, and exposes a user-triggered Reset View action. Reveal spin and
  nonessential juice are disabled by Reduced Motion.
- **Touch input is explicit.** Hammer/Mark are visible toolbar choices.
  Double-tap no longer silently changes the tool; it cannot replay an edit.
  Pinch and drag remain orbit-only, and focus loss cancels gestures.
- **The voxel render path stays MultiMesh-first.** Canonical state remains in
  dictionaries; clue hosts are bare `VoxelBlock` nodes created with
  `VoxelBlock.new()` instead of a full `Block.tscn` per cell. The old heavy
  scene remains available for isolated tooling/tests but is not instantiated
  for every gameplay cell.
- **Clue information stays ordered.** Group arrays render as `1·2` rather than
  collapsing `[1,2]` and `[2,1]` to the same total.
- **Audio is restrained and activity-specific.** The bundled Kenney Interface
  Sounds 1.0 pack is CC0 and already used for chisel, mark, error, toggle, and
  victory. Pooled players avoid per-action node churn; menu movement, round
  start, combo pitch, and haptics are routed through `AudioManager`.
- **Replay is local-first.** A visible seed and share token support
  `Retry this seed` and `New random run`; the existing bounded run history is
  the source for archive sharing. No account or network is required.
- **Achievements are local-first with a platform seam.** The 17 stable local
  achievements remain in `AchievementService`. `AchievementPlatform` queues
  unlocks for a future Android `PlayGames` singleton and stays offline-safe.
  `data/achievements/google_play_manifest.json` deliberately has empty Console
  IDs until a real Play project is registered.
- **Persistence is recoverable.** Save writes use a temporary file, rotate a
  backup, validate JSON before commit, and recover from a corrupt primary.
  The UI does not claim a gacha result was saved when the write fails.
- **2D modes stop rendering the 3D target.** The root scene dynamically sizes
  the SubViewport for the active landscape container and disables its update
  while menu, compendium, archive, or settings are visible.

## Asset policy

Approved now:

- Kenney Interface Sounds 1.0 — CC0 1.0; source, filenames, and changes are
  recorded in `ASSETS.md` and the bundled license file.
- The generated panorama/icon — project-created CC0; the panorama is used as a
  low-opacity menu backdrop.

For future art, prefer Poly Haven or ambientCG only after recording the exact
asset page, author, license, version, hash, modifications, and store/DRM
compatibility. Do not ship previews, ripped store assets, or assets with an
unreviewed non-commercial/DRM license. Achievement icons should be original
512×512, text-free, and circular-crop tested.

## High-value follow-up experiments

1. Profile a low-end arm64 device: grid build, clue update, slice drag, round
   transition, frame-time P90/P99, memory, startup, and 20-minute thermal run.
2. Pool only visible clue hosts and incrementally update MultiMesh slots.
3. Add a text/coordinate board alternative and non-color cell states.
4. Define real, tested wave rules and a visible reserve use before restoring
   BLITZ/FOG/BOSS labels.
5. Produce a signed API-36 AAB and internal-track PGS adapter with outage and
   account-switch tests.

## References

- Godot 4.7 performance and MultiMesh guidance:
  <https://docs.godotengine.org/en/4.7/tutorials/performance/general_optimization.html>
  and <https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html>
- Godot Android export and plugins:
  <https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html>
  and <https://docs.godotengine.org/en/4.7/tutorials/platform/android/android_plugin.html>
- Google Play Games quality and achievements:
  <https://developer.android.com/games/pgs/quality>
  and <https://developer.android.com/games/pgs/achievements>
- Android vitals and memory:
  <https://developer.android.com/games/optimize/vitals>
  and <https://developer.android.com/games/optimize/memory-reduction>
- Kenney Interface Sounds:
  <https://kenney.nl/assets/interface-sounds>
- Poly Haven license: <https://polyhaven.com/license>
- ambientCG license: <https://docs.ambientcg.com/license>
