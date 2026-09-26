# Google Play Games achievements handoff

The game currently has a complete **offline-first** achievement system in
`scripts/AchievementService.gd`. `SaveManager` commits local progress and then
forwards newly unlocked IDs to the optional `AchievementPlatform` boundary.
The game is playable if Android, authentication, or Play Games is unavailable.

## What is implemented

- Stable local IDs, versioned definitions, incremental progress, and idempotent
  event IDs live in the domain service.
- `scripts/AchievementPlatform.gd` is a no-network adapter boundary. It queues
  bounded unlock events and will call a `PlayGames` Android singleton only
  when a future plugin is present, and it refuses to forward an achievement
  whose manifest `play_games_id` is still blank — that event stays queued
  instead of being pushed as a placeholder Console id.
- `data/achievements/google_play_manifest.json` is the reviewable mapping
  checklist. Console IDs and icon paths are intentionally blank because neither
  the Play Console project nor the icon art exists yet; placeholder values must
  never be shipped. `npm run verify:achievements` fails the build if the manifest
  drifts from the local definitions or points at a missing icon file.

## Before enabling the platform upload

1. Register the signed Android App Bundle in Play Console and create the 17
   visible achievements. Use the local IDs in the manifest as the source of
   truth, and fill `play_games_id` only after the Console values are known.
2. Create a Godot Android v2 plugin (Kotlin/Java) exposing a small
   `PlayGames` singleton. Keep the plugin optional and guard every call with
   `Engine.has_singleton("PlayGames")`.
3. Use PGS v2 authentication and queue local unlocks until the player is
   authenticated. Handle denied auth, account switching, offline mode, quota
   errors, and service outages without clearing the local queue.
4. Configure the debug and release SHA-1 fingerprints separately. Verify the
   release certificate, API level, 16 KB page-size compatibility, and the PGS
   dependency in a real arm64 build.
5. Add 512x512 achievement icons, drop them in the repo, and fill the `icon`
   field in the manifest so the verifier passes. Keep them text-free, legible
   when cropped to a circular toast, and record their source/license in
   `ASSETS.md`. The existing Kenney Interface Sounds pack is already documented
   as CC0; do not copy assets from an unverified preview or store listing.
6. Add privacy-policy, data-safety, account-deletion, and Play Console
   disclosure notes before enabling any cloud or identity feature.

## Testing contract

The first bullet is covered today by the offline unit test
`test/unit/test_save_manager.gd::test_achievement_events_persist_idempotently`,
and "disabling Play Games never blocks play" is exercised by every current run,
because no plugin exists in any build. The authentication, quota, and
upload-failure bullets below describe the contract a future Play Games plugin
must satisfy; with no plugin and no Play Console project, they are **not**
currently exercised by any test or device run.

- Local unlock works with no network and survives reload.
- A queued event is sent at most once after authentication.
- Disabling Play Games never blocks puzzle start, completion, or profile load.
- A failed upload leaves the local unlock intact and can be retried.
- An achievement with a blank `play_games_id` is never forwarded to a plugin;
  it remains queued until the manifest is filled in. This one is enforced in
  `AchievementPlatform.resolve_console_id` and covered by reading the code
  only, not by a test.
- The adapter **is** bundled with the production Web export. `AchievementPlatform`
  is an autoload, and the `Web` preset's `exclude_filter` does not list
  `scripts/AchievementPlatform.gd` or `data/achievements/`, so the release PCK
  contains `AchievementPlatform.gdc` and `google_play_manifest.json`. Shipping it
  is inert rather than dangerous: with no Android `PlayGames` singleton present,
  `is_available` stays false, nothing is forwarded, and the adapter makes no
  network call. The release scan (`tools/verify-web-release.js`) fails only on
  `test_bridge`, `gameAPI`, and `addons/gut`, so it does not check for the
  adapter and is not expected to.
- What the production Web export does not contain is the plugin itself: no
  `PlayGames` singleton exists, so no Play Games code path is reachable from
  the shipped build.
