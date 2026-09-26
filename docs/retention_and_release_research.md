# Mixing Flavors: retention, replay, and release research

**Review date:** 2026-09-25  
**Scope:** the supplied GDD/TDD, the current Godot vertical slice, and official platform guidance. This is a product/engineering decision record, not a claim that the current build is production-ready.

## Executive conclusion

The strongest differentiator is not a larger meta-layer; it is a trustworthy 3D deduction loop with a clear reason to return. The recommended order is:

1. Make the first five minutes understandable and bug-free.
2. Make every run fair, deterministic, and replayable.
3. Add optional daily/local mastery loops.
4. Add collection and archive meaning without pay-to-win or streak punishment.
5. Add platform achievements/leaderboards only after score and anti-cheat boundaries are trustworthy.

The game should preserve offline play. Network features may improve convenience, but must never be required to finish a puzzle, recover a local profile, or access the core archive.

## Evidence and implications

### Deterministic puzzle trust

A puzzle is not content until its displayed clues have exactly one complete solution matching the target. A JSON `solvable` or `runtime_validated` flag is metadata, not proof. The current implementation now validates player-facing custom puzzles in strict mode and has a strict catalog release check.

**Product implication:** never ship a puzzle whose only validation is a producer assertion. Reject malformed content before an interactive grid exists.

### Fair return loops

The supplied GDD's fixed 120-second round contract is a useful fairness anchor. Banked time should be visible and intentional, not silently disappear. A daily challenge is valuable when it is optional, offline, UTC-deterministic, catch-up friendly, and non-punitive.

**Product implication:** use a daily sequence and local best result to invite a return without energy timers, expiring streaks, forced prompts, or randomized paid pressure.

### Replay and mastery

Seeds, ruleset/catalog versions, and sequence fingerprints make a result explainable and reproducible. They also provide the foundation for fair local history and later platform leaderboards.

**Product implication:** show the seed and version context in results; distinguish “retry this seed” from “new random run.” A leaderboard must submit the same canonical score shown to the player.

### Collection and disclosure

The archive is only motivating if entries have a stable identity, source, rarity, duplicate policy, mastery meaning, and a visible non-power advantage. Gacha disclosure is a trust feature: show cost, rates, pity state, and duplicate conversion before a roll.

**Product implication:** a text list can be a vertical-slice placeholder, but a polished release needs locked/acquired states that do not rely on color alone and a reason to revisit the archive.

### Accessibility and platform quality

Touch targets, safe areas, reduced motion, non-color state cues, keyboard navigation, and readable text are gameplay quality—not optional polish. Google Play's quality guidance and Android vitals guidance should be treated as release gates. A release artifact must be tested on real arm64 devices; a desktop/mobile browser smoke test is not a substitute.

## Implemented in this iteration

- Curated deterministic catalog and difficulty routing.
- Strict player-facing puzzle validation and repaired canonical tutorial clues.
- Visible Daily Challenge entry point backed by `DailyChallengeService`.
- Optional local `AchievementService` with versioned definitions, incremental progress, idempotent events, persistence, and no gacha-luck unlocks.
- Separate production `Web` and test-only `WebTest` presets; production has no test bridge/API.
- Responsive title, Compendium, Archive, HUD, tool tray, safe-area layout, and camera framing.
- Compendium completion persistence, tutorial semantic line detection, visible tutorial entry point, and fixed 120-second fallback.
- Local gacha seed initialization, persistent haptics preference, visible banked-time reserve, persistent daily/achievement/profile collections, and bounded local run history/share tokens.

## Prioritized next experiments

### P0 — trust and retention foundation

- Finish transactional save/replace writes and crash-injection tests.
- Add run summaries and seed replay/share to the visible results flow.
- Define ranked score ownership and reject test-generated scores.
- Expand the runtime catalog beyond the current 30 entries with strict fingerprints.
- Profile and reduce the remaining 5×5 node/thermal cost on reference Android devices.

### P1 — meaningful engagement

- Add three visible, deterministic pre-round strategy choices.
- Give BLITZ/FOG/BOSS labels real, tested mechanics or remove them.
- Add mastery-based cosmetic/archive progression.
- Add accessibility settings for reduced motion, haptics, text scale, and non-color cues.
- Prepare an optional PGS v2 adapter for sign-in, achievements, leaderboards, and cloud save.

### P2 — platform/live operations

- Signed API-36-compatible AAB and Play Console internal track.
- PGS v2 adapter with offline/guest fallback and tested network failures.
- Content-hashed Web caching/PWA decision.
- Signed, offline-safe seasonal catalog/config delivery with rollback.

## Guardrails

- No randomized real-money sales.
- No energy walls, streak loss, pay-to-continue, or hidden difficulty increases.
- No client-only trust for ranked scores.
- No required backend for core play.
- No parallel gameplay authority: extend `GauntletManager`, `PuzzleManager`, `SaveManager`, and the existing UI flow.

## Official references

- Supplied GDD/TDD export: <https://docs.google.com/document/d/1VlCW_qPvkWGEckEP8yZzzppw7oQyRT5jejDk4KaLtDQ/export?format=txt>
- Google Play Games achievements quality: <https://developer.android.com/games/pgs/quality>
- Google Play Games leaderboards: <https://developer.android.com/games/pgs/leaderboards>
- Godot 4.7 Android export: <https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html>
- Godot 4.7 input propagation: <https://docs.godotengine.org/en/4.7/tutorials/inputs/inputevent.html>
- Android game vitals: <https://developer.android.com/games/optimize/vitals>
- Android memory reduction: <https://developer.android.com/games/optimize/memory-reduction>
