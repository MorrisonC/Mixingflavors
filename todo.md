# Mixing Flavors: Voxel Gauntlet — Product & Release Backlog

This file is the single source of truth for product work, release gates, and research follow-up. It is intentionally staged: preserve the deterministic voxel/Picross core, improve decision quality and presentation, then add platform services only after the local game is trustworthy.

## Product contract and guardrails

- Keep the 3D Picross/chisel/mark/slice loop deterministic and solvable without guessing.
- Keep the 120-second Gauntlet clock as a hard round contract; banked time must have a visible, tested purpose or be removed.
- Keep offline play fully functional. No energy timers, streak punishment, forced ads, pay-to-continue, or randomized real-money sales.
- Landscape-first Android/Web presentation remains the shipping contract. The GDD contains an orientation example that conflicts with its landscape display requirement; the implementation uses landscape (`window/handheld/orientation=0`) until a separate portrait mode is designed and tested.
- The full GDD describes 10,000+ source puzzles and a 3D museum. The current vertical slice intentionally ships a fast, strict 30-entry runtime catalog; content expansion must be lazy-loaded and fingerprinted rather than parsed at startup.
- Google Play Games, cloud save, public leaderboards, and remote catalogs require account/project credentials and must remain behind optional adapters; they must never be required to play offline.

## Completed baseline

- [x] Rename the project to `Mixing Flavors: Voxel Gauntlet` and establish the 2460×1080 landscape reference canvas.
- [x] Add deterministic runtime catalog loading and fast puzzle selection.
- [x] Centralize difficulty thresholds and 120-second gauntlet banking rules in domain services.
- [x] Route difficulty selection into a loaded puzzle and keep Gauntlet Continue inside the run.
- [x] Add persistent profile, completion, inventory, shards, and deterministic pity/duplicate gacha logic.
- [x] Add archive/gacha UI and deterministic unit coverage for catalog, gauntlet, save, and gacha services.
- [x] Remove generated builds, reports, vendored dependencies, telemetry systems, patch debris, legacy art, and brittle visual snapshots.
- [x] Establish a fresh Web export pipeline and serial browser-test harness.

## Active polish sprint — 2026-09-25

This sprint is intentionally focused on trust and mobile feel before adding more
content or monetization. Work is tracked here so each screen change has a
measurable acceptance check.

- [x] **P0-9 — Make the victory result truthful and readable:** queue result data
  until the result scene is ready, render level/time/score/stars/seed/best
  context, keep the overlay above the 3-D canvas, and prove the labels are
  non-empty after a real solve.
- [x] **P0-10 — Add visible replay decisions:** expose `Retry this seed` and
  `New random run` separately, show the seed/share code, and route each action
  through the existing `GameManager`/run owner rather than inventing a second
  gameplay authority.
- [x] **P0-11 — Remove the voxel node cliff:** replace full `Block` scene
  instances used only for clue hosts with lightweight clue nodes while keeping
  canonical state, MultiMesh rendering, labels, undo, and input behavior intact.
- [x] **P1-11 — Tune activity feedback and camera:** keep the three-quarter
  readable framing, damp orbit/zoom, add restrained tool/combo/round cues, and
  honor a reduced-motion setting for reveal/confetti effects.
- [x] **P1-12 — Polish menu and short-landscape layouts:** use safe-area
  spacing, 44–48dp targets, focus-visible states, a compact result card, and a
  profile/best-run summary without hiding primary actions.
- [x] **P1-13 — Prepare Google Play achievements safely:** keep the existing
  offline local achievements authoritative and add a thin, testable optional
  platform adapter boundary plus release documentation; no network dependency
  may block play. The shipped manifest must not claim Console ids or icon files
  that do not exist, and the adapter refuses to forward an achievement whose
  Console id is still blank.
- [x] **Verification — completed 2026-09-25.** GUT 164/164 (1283 assertions) on
  Godot 4.7.2, a fresh `WebTest` export with the serial Playwright suite at
  14/14, a fresh production `Web` export with a clean release scan, and both
  content gates (`verify:catalog`, `verify:achievements`). Details and the
  explicit device-only gaps are in the verification section at the end of this
  file.

## Current stabilization — P0 release blockers

### P0-1 — Finish the current UI/gameplay repair and prove it on a fresh Web build

- [x] Verify the repaired title, neutral studio palette, camera fit/initial three-quarter view, non-overlapping HUD, archive layout, victory/defeat modals, and Compendium completion flow at desktop and narrow landscape sizes.
- [x] Make the Gauntlet fallback fail closed at exactly 120 seconds; remove the legacy 300-second fallback.
- [x] Ensure difficulty selection always produces an active puzzle, visible loading state, and deterministic selected ID before input is enabled.
- [x] Add browser coverage for difficulty → puzzle, solve → victory, Continue, Leave confirmation, retry, Compendium navigation, and Daily Challenge launch.
- [x] Add geometry assertions for title/HUD/modal bounds and a smoke assertion for console/page errors.
- [x] Acceptance: GUT is green with no unexpected engine errors; fresh Web export succeeds; browser tests pass serially from a clean build with no page/console errors; the deterministic test bridge is isolated to `WebTest`.

### P0-2 — Remove the test bridge from production artifacts

- [x] Separate the test-only Web preset (`WebTest`, `e2e` feature) from the production `Web` preset.
- [x] Expose `window.gameAPI`, automatic solving, arbitrary mode switching, and node inspection only in the test export.
- [x] Add a release-PCK scan that fails if `test_bridge.gd`, GUT markers, or test-only API resources are present (`npm run verify:web` runs in CI).
- [x] Acceptance: production Web has no `window.gameAPI`; Playwright uses the dedicated test export; release size and content checks are automated.

### P0-3 — Establish one authoritative Gauntlet contract

- [ ] Make `GauntletManager` the sole owner of selected puzzle, depth, timer, score, streak, mistakes, rewards, and difficulty state.
- [ ] Define Easy/Medium/Hard as either practice presets or remove them from ranked selection; ranked Endless must follow the documented depth/dimension curve.
- [ ] Make every displayed BLITZ/FOG/BOSS state have a deterministic mechanical and scoring effect, or remove the label.
- [ ] Give banked time a visible strategic use (for example, a clearly capped, player-chosen continuation reserve) or remove it from player-facing claims.
- [x] Use one score formula and include catalog/ruleset version, difficulty, depth, seed, and sequence fingerprint in a persisted run summary.
- [ ] Acceptance: 100 fixed seeds produce identical 31-round puzzle-ID/sequence hashes; every round starts at 120 seconds; retry-seed and new-random-run are separate tested actions.

### P0-4 — Make player-facing puzzle validation fail closed

- [x] Ignore caller-supplied `runtime_validated`, `solvable`, and equivalent trust flags in `GridManager`.
- [x] Strictly validate stored player-visible clues, require exactly one complete solution, and ensure it matches the target.
- [x] Reject malformed/duplicate/empty catalogs and fail with a safe non-interactive error state.
- [ ] Add a catalog fingerprint/version to the build manifest and CI content-integrity gate.
- [ ] Acceptance: changing a target, clue, dimension, or ID in a test fixture causes build/runtime rejection; invalid content never creates an interactive grid.

### P0-5 — Repair first-run onboarding

- [x] Offer a visible, resumable tutorial entry point for new profiles (automatic first-run routing remains a follow-up).
- [x] Connect camera-orbit and semantic deduction steps after touch controls are initialized; never use hidden controls or hard-coded fixture coordinates.
- [x] **Write the rules down instead of only demonstrating them.** `How to Play`
  now opens a scrollable rules card (the goal plus clue/Hammer/Mark/Slice/orbit/
  Undo+Hint) and only enters the guided practice through an explicit
  `Start guided practice` action. The button previously loaded the puzzle
  immediately, so the one screen named "How to Play" answered nothing.
- [x] **Deliberate contract change:** the guided banner label shipped with
  `max_lines_visible = 0`, which clips a label after *zero* lines. Every step
  assigned its instruction correctly and the player still saw an empty bar
  stacked on top of the puzzle's own near-identical HUD panel, which is why
  onboarding looked like it had no instructions. It is now `-1`, the banner is
  laid out below the measured HUD rect, and a unit test fails if the label is
  ever clipped to zero lines again.
- [ ] Make skip/replay persistence truthful and ensure completion is recorded only after the intended final deduction.
- [ ] Acceptance: a real pointer/touch test can complete every tutorial step; a first-time player can understand the objective without facilitator help.

### P0-6 — Make persistence and economy transactional

- [ ] Choose one authoritative save per platform; use atomic/replace writes, schema validation, backup/recovery, and pause/resume saves.
- [ ] Persist themes, trophies, mastery, run summaries, achievements, settings, completion, gacha seed/roll count, and immutable roll receipts.
- [ ] Generate the first gacha seed once, persist it, and make applying a result exactly-once even across a crash/reload boundary.
- [ ] Acceptance: corrupt/older saves migrate safely; crash-injection tests do not duplicate or lose currency/items; the UI never reports success when persistence fails.

### P0-7 — Produce a signed, API-36-compatible Android App Bundle

- [x] Finalize package ID, version code/name, adaptive/themed icons, permissions, ABI policy, and min/target SDK. `com.morrisonc.mixingflavors.voxelgauntlet`, versionCode 1 / versionName 0.1.0, minSdk 24, target/compileSdk 36, `arm64-v8a` + `armeabi-v7a`, VIBRATE only, edge-to-edge on, adaptive + monochrome launcher icons.
- [x] Use a protected keystore and export an AAB for Play; verify with `bundletool` and `apksigner`. `npm run build:android` injects the upload key from protected environment variables and restores the committed preset afterwards; `npm run verify:android` runs 29 checks over the built bundle. A 51.7 MB signed AAB was produced and passed every check on 2026-09-26.
- [x] Exclude tests, test bridge, source corpus, development tools, and secrets from the bundle. The 25 MB `assets/puzzles/*_puzzles.json` corpus and the build-only `puzzle_manifest.json` are excluded; the runtime catalog and the curated per-theme models are not.
- [x] Record the release gate, the build recipe, the signing layout, and the Play Console upload steps in `docs/android_release.md`.
- [ ] **No device run.** The bundle has never been installed on a physical arm64 phone or an emulator, so frame rate, memory, thermal behaviour, safe areas, audio focus, haptics, pause/resume and process recreation remain unmeasured.
- [ ] **No real Play upload.** The AAB has not been through Play Console validation, so target-API, data-safety and content-rating findings are still outstanding, and Play App Signing enrolment has not been performed.
- [ ] **No CI signing.** The keystore is injected from local environment variables only; a protected CI secret and an upload-key rotation plan are still open.
- [ ] **16 KB page size proven only statically.** `verify:android` reads the ELF `PT_LOAD` segments and confirms the 64-bit libraries declare 0x4000 alignment; no 16 KB-page-size device has run the app.
- [ ] Acceptance: a clean CI checkout produces a signed AAB, installs/starts on an arm64 device, survives background/resume, and records build metadata.

### P0-8 — Remove the 5×5 performance cliff

- [ ] Keep canonical voxel state and MultiMesh rendering, but stop creating full `Block` scene trees (collision, mesh, particles, labels, sprites) for every hidden/unresolved cell.
- [ ] Pool/reuse visible clue hosts and cap particle/label work by active slice.
- [ ] Profile low/mid/high Android devices for frame time, memory, startup, and a 20-minute gauntlet thermal run.
- [ ] Acceptance: agreed 60 FPS/30 FPS floors, bounded node/memory counts, no thermal throttling in the test window, and unchanged clue/input/win behavior.

## Engagement and strategy — P1

### P1-1 — Optional Daily Challenge (delegated slice)

- [x] Derive a UTC daily ID from date plus an explicit ruleset/catalog version.
- [x] Give every offline player the same deterministic puzzle sequence; store one result and allow catch-up without punishment.
- [x] Keep notifications opt-in/off by default; never remove currency or revoke badges for missed days.
- [x] Acceptance: same date/ruleset always yields the same first 31 puzzle IDs; a local result survives reload; no network is required to start/finish.

### P1-2 — Seed replay and run sharing

- [x] Display seed, difficulty, ruleset/catalog version, and sequence fingerprint in persisted run summaries.
- [x] Add explicit share-token validation and a copy action for the latest local run code.
- [x] Store a bounded, user-visible run summary without resurrecting the deleted telemetry/run-history system.
- [ ] Add visible `Retry this seed` / `New random run` controls and a paste/share import flow; old catalog versions are labeled rather than silently rerolled.

### P1-3 — Strategy systems with visible tradeoffs

- [ ] Make combo, heal thresholds, hints, mistake penalties, and banked time visible before they matter.
- [ ] Add three meaningful pre-round decisions that do not require hidden information (for example safe scan, focused clue audit, or aggressive time bonus), each with deterministic tests and accessible text.
- [ ] Give BLITZ/FOG/BOSS real rules and counterplay; do not use labels as cosmetic difficulty spikes.
- [ ] Acceptance: a playtester can explain why a chosen strategy was better; no strategy creates an unearned advantage in offline deterministic verification.

### P1-4 — Achievement system (local first, PGS adapter later)

- [x] Define versioned achievement IDs, descriptions, progress metrics, and unlock conditions in data—not display names.
- [x] Ship at least 10 visible achievements, with at least four achievable by nearly everyone within one hour and incremental progress for core actions.
- [x] Persist local unlocks offline; upload remains a future optional PGS v2 adapter.
- [x] Acceptance: no achievement depends primarily on gacha luck; unlocks are idempotent; network failure never blocks play or loses progress.

### P1-5 — Local score/rank presentation and future leaderboards

- [x] Display best depth, score, and streak locally, with a copyable latest-run code.
- [ ] Display daily results and a browsable recent-seed list locally.
- [ ] Submit to Google Play Games v2 only after the canonical score, anti-cheat boundary, and test-bridge removal are complete.
- [ ] Keep a server-side validation path for cross-platform ranked play; never trust a client-reported score.
- [ ] Acceptance: the displayed score equals the eligible submitted score; offline scores remain visible when services are unavailable.

### P1-6 — Archive/collection depth

- [ ] Give every item a display name, source puzzle/theme, rarity, duplicate policy, mastery description, and a real 3D/thumbnail presentation.
- [ ] Add locked/acquired styling that does not rely on color alone; support 200% text scale and short landscape.
- [ ] Show pity-adjusted rates and duplicate conversion before a roll and in a receipt.
- [ ] Acceptance: collection progress and mastery survive relaunch and provide a visible non-pay-to-win benefit or cosmetic purpose.

### P1-7 — Difficulty calibration and content variety

- [ ] Playtest Easy/Medium/Hard with target completion and action-budget thresholds; rework hard if it is control-blocked rather than reasoning-blocked.
- [ ] Expand to at least 30 strict-valid entries per tier and prevent adjacent repeats in a 30-round seeded session.
- [ ] Lazy-load compendium shards only after a measured cold-start budget; preserve fingerprints and strict validation.
- [ ] Acceptance: content is balanced against recorded criteria, not intuition alone; no puzzle is ambiguous under displayed clues.

## Accessibility, presentation, and platform polish — P1

### P1-8 — Accessibility and reduced motion

- [ ] Add non-color shape/icon/text states for marked, hidden, destroyed, error, combo, and selected cells.
- [x] Add persistent haptics setting and route touch feedback through it (reduced-motion setting remains).
- [x] Retire the `High contrast cues` checkbox: it was persisted and offered in
  the settings panel but read by no consumer anywhere, so it did nothing. The
  key is now dropped on load (`SaveManager.RETIRED_SETTING_KEYS`) and the
  checkbox is detached at runtime. Follow-up: delete the stale
  `HighContrastCheck` node from `scenes/MainMenu.tscn` when that scene is next
  edited.
- [ ] Reduced motion disables auto-spin, confetti, shake, pulsing, and nonessential particles.
- [ ] Provide keyboard navigation and a text/coordinate alternative for the voxel grid; verify 48dp targets and 200% text.
- [ ] Acceptance: automated checks plus manual TalkBack/keyboard testing on the release candidate.

### P1-9 — Google Play Games v2 and store readiness

- [ ] Add a thin optional Android adapter for sign-in, achievements, leaderboards, and cloud save; guest/offline play remains complete without it.
- [ ] Use PGS v2 only, protect debug/release SHA-1 configuration, and test denied auth/network/service-unavailable states.
- [ ] Publish a privacy policy, data-safety inventory, account/deletion instructions, and accurate timer/gacha disclosures.
- [ ] Acceptance: tester accounts can unlock/submit/load through PGS v2; no PGS outage blocks the core game.

### P1-10 — Web delivery and quality gates

- [ ] Decide whether PWA/installability is required; if not, document the choice and keep the game usable without service workers.
- [ ] Add content-hashed caching/revalidation for WASM/PCK while preserving COOP/COEP/CORP and path protections.
- [ ] Run GUT, strict catalog validation, fresh export, real-input Playwright, Android smoke, and performance gates from a clean checkout; upload logs/metadata/fingerprints.
- [ ] Acceptance: repeat visits avoid redownloading the engine payload, and release CI cannot publish an untested artifact.

## Later experiments — P2

- [ ] Optional cross-device profile sync with explicit conflict resolution.
- [ ] Signed, offline-safe seasonal catalog/config delivery with rollback; ranked rules never change silently.
- [ ] Only after core retention is healthy, evaluate transparent non-random cosmetics/entitlements. Do not sell randomized real-money rolls.

## Verification status — 2026-09-25 (current, after the honesty/UX fixes)

All three local gates were re-run after the final edit on 2026-09-25.

- [x] **GUT headless on Godot 4.7.2: 195/195 tests, 1418 assertions, all
  passing.** Coverage added this session includes grouped-clue totals, the
  time-bomb overlay, an empty `register_clear` result, the abandoned victory
  wait, the retired `high_contrast` key, the Play Console id mapping, the
  save-revision and transactional-rollback contracts, the JSON round trip for
  daily run history, share-token tamper and version rejection, mint
  transactional rollback and replay rejection, undo restoring the combo, the
  camera distance floor and `reset_view` recovery, and the long-press contract.
- [x] **Fresh `WebTest` export + serial Playwright: 20 passed, 2 skipped
  (10.4 min)**, including the mobile landscape project, re-run after every
  round. The 2 skips are the two touch-dispatch tests on the non-touch desktop
  project, which is correct and reported rather than hidden. The engine-ready
  budget was raised to 120 s because the 39 MB `index.wasm` can legitimately take
  over a minute to compile on a loaded machine; that is a harness budget, not a
  product assertion, and a genuine boot failure still fails fast.
- [x] **Real mobile touch coverage now exists.** The previous mobile browser
  test navigated to puzzle *selection* and never instantiated the puzzle scene,
  so no toolbar, camera, or touch Control was ever built; it would have passed
  with the entire touch layer deleted. `tests/playwright/mobile_touch.spec.js`
  loads a real puzzle and asserts that a dispatched touch tap chisels the voxel
  the game's own raycast resolves, that a stray tap on the empty toolbar cannot
  swallow the next tap, that every control is inside the viewport, at least 40
  units tall, and non-overlapping, and that the camera is auto-fitted, cannot be
  pinched inside the puzzle, and is restored by Reset View.
- [x] **Fresh production `Web` export + release scan passed:** the PCK contains
  no `test_bridge`/`gameAPI`/GUT markers. Note the scan only fails on those
  markers, so it never proved the production PCK was free of other content;
  that PCK does contain `AchievementPlatform.gdc` and
  `google_play_manifest.json`. See `docs/google_play_achievements.md`.
- [x] **Content gates:** `npm run verify:catalog` (30 entries) and
  `npm run verify:achievements` (17 entries) both pass, and the achievement
  verifier was negative-tested against a placeholder Console id, a missing icon
  file, an unknown local id, a missing manifest entry, and a duplicate id.
- [x] **The starting screen is no longer a flat gray panel.** The menu drew a
  90%-opaque near-white `Panel` on top of the panorama, so the bundled artwork
  contributed roughly a tenth of the final pixel and the whole screen collapsed
  to one washed-out value. The panorama now renders at full opacity under a
  vertical gradient scrim, the buttons sit on a glass card, `Play Gauntlet` is
  an amber primary, and the keyboard focus ring is an outline instead of an
  opaque navy fill that used to paint over the primary button. The puzzle
  environment likewise moved from a near-white sky to a deep-indigo/rose
  gradient so the translucent voxel bodies and their clue numerals separate
  from the background.
- [x] **Deliberate contract change:** `hammer_cell`, the primitive that writes
  cell state, now refuses to destroy a kept voxel. The rule previously lived
  only in the click handler, so any new caller could have destroyed a target
  with no mistake charged and no undo entry, leaving the round unwinnable while
  looking perfect. Three existing tests built their scenario through that path
  and were updated to assert the stronger guarantee; their original intent
  (a destroyed target must not count as won) is still covered by corrupting
  state directly.
- [x] **Regression classes found and fixed, now covered by tests:** grouped
  clues parsing to `0` and rendering as the red unknown marker; the time-bomb
  pulse and sculpture tint being silently dead after the lightweight clue-host
  change; an empty `register_clear` paying shards and re-running a depth;
  `_fail_gauntlet` showing `GameOver` behind a hidden HUD; the victory watcher
  stranding a touch player; a false "code copied" claim; a `high_contrast`
  checkbox that nothing read; the web backup being a copy of the new payload;
  load order silently rolling a player back; rewards shown but not stored; the
  entire run history being rejected by a catalog hash supplied as a sequence
  fingerprint; a stored daily `daily_id` becoming a float on reload and
  poisoning run history permanently; the daily identity drifting from the
  catalog it selects from; retrying a daily replaying it as a plain run; daily
  stars derived from healable HP; a failed mint claiming a refund that never
  happened; a replayed mint rewinding the seed chain; undisclosed pity raising
  the real rare rates above the published ones; and undo leaving the combo
  intact so re-chiselling laundered the mistake budget and inflated the score.
- [x] **Camera and touch blockers fixed and proven in a browser:** Reset View
  only restored orientation, so the advertised recovery action recovered
  nothing; and the zoom floor was a constant, letting the camera be pinched
  inside a puzzle where every ray resolved to a single cell and the whole screen
  became one un-chiselable target. The fit now derives the floor from each
  puzzle's radius and Reset re-fits the distance. The gauntlet toolbar also
  passed touches through, so a tap on an empty toolbar cell anchored the
  double-tap window and silently discarded the player's next real chisel. Also
  fixed: a 1px mouse jitter cancelling a click, a drag slop of ~4dp on a
  high-density panel, a still long press swallowing the tap entirely, a marked
  voxel being hammered with no feedback, Escape re-opening an already-visible
  confirm dialog, the camera ignoring reduced motion while the camera shake
  honoured it, a viewport resize discarding the player's chosen zoom, and
  `get_property_list()` rebuilds inside the per-pointer-event raycast.
- [ ] **No Android evidence of any kind:** no Android export, no AAB, no
  signing, no bundletool/apksigner run, no emulator, and no physical device.
  None of the verification above covers Android. `docs/android_release.md`
  records the checked-in preset state instead.
- [ ] **No mobile performance or thermal evidence:** all timing above comes
  from a desktop browser and a 851x393 emulated viewport. The 39 MB
  `index.wasm` dominates real mobile load time and has not been measured on a
  device.
- [ ] **No live Google Play Games result:** the adapter has only been reviewed
  by reading code. It stays unavailable because no `PlayGames` plugin exists.
- [x] **Verified by reading code on 2026-09-25:** the victory and archive
  copy actions now report success only when a copy is actually confirmed (a
  synchronous native `DisplayServer` clipboard, or a web `writeText` promise
  that the injected JavaScript reported as resolved), and otherwise show the
  code with a neutral copy instruction. The suite and browser runs above prove
  the screens still boot, render, and navigate; the success/failure *branch* of
  the clipboard confirmation has not been exercised in a real browser, because
  the automation cannot grant or deny clipboard permission.

## Historical verification snapshot — last full run, before the 2026-09-25 fixes

Kept for history. These results are from the last clean full-suite run and
predate the honesty/UX fixes above; do not quote them as current state.

- [x] GUT: 141/141 tests, 1137 assertions on Godot 4.7.1; no unexpected engine errors or child-leak warnings in the final run.
- [x] Fresh `WebTest` export: 14/14 serial Playwright tests passed, including Compendium persistence, Daily Challenge, tutorial entry, archive, and gameplay flows.
- [x] Fresh production `Web` export: verified `window.gameAPI === undefined`; production PCK contains no `test_bridge`/`gameAPI` payload.
- [x] Re-run the final GUT/Web checks after the last presentation-only edit; local Playwright servers are stopped before handoff.

## Research basis (2026-09-25)

- Supplied GDD/TDD export: `https://docs.google.com/document/d/1VlCW_qPvkWGEckEP8yZzzppw7oQyRT5jejDk4KaLtDQ/export?format=txt`
- Google Play Games achievements quality checklist: https://developer.android.com/games/pgs/quality
- Google Play Games leaderboard guidance: https://developer.android.com/games/pgs/leaderboards
- Godot 4.7 Android export/AAB guidance: https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html
- Godot 4.7 input event propagation: https://docs.godotengine.org/en/4.7/tutorials/inputs/inputevent.html
- Android vitals and memory guidance: https://developer.android.com/games/optimize/vitals and https://developer.android.com/games/optimize/memory-reduction

Research conclusion: extend the existing manager-oriented architecture rather than adding parallel gameplay authorities. The first new engagement feature should be deterministic, optional, and useful even without a backend.
