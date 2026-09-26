extends GutTest

const SaveManagerClass = preload("res://scripts/SaveManager.gd")
const GachaServiceClass = preload("res://scripts/GachaService.gd")


func before_each() -> void:
	var path: String = "user://test_mixing_flavors_savegame.json"
	for candidate: String in [path, path + ".backup", path + ".tmp"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func after_each() -> void:
	var path: String = "user://test_mixing_flavors_savegame.json"
	for candidate: String in [path, path + ".backup", path + ".tmp"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func test_default_schema_and_completion_persistence() -> void:
	var manager: Node = SaveManagerClass.new()
	manager.set("path_override", "user://test_mixing_flavors_savegame.json")
	add_child_autoqfree(manager)
	manager.call("load_game")
	var stats: Dictionary = manager.call("get_player_stats")
	assert_eq(int(stats.get("total_shards", -1)), 0)
	manager.call("add_shards", 50)
	var completion: Dictionary = manager.call("record_puzzle_completion", "puzz_001", 2, 45.2)
	assert_eq(int(completion.get("stars", 0)), 2)
	var loaded: Node = SaveManagerClass.new()
	loaded.set("path_override", "user://test_mixing_flavors_savegame.json")
	add_child_autoqfree(loaded)
	var loaded_data: Dictionary = loaded.call("load_game")
	assert_eq(int(loaded_data.get("player_stats", {}).get("total_shards", 0)), 50)
	assert_true(loaded_data.get("completion", {}).has("puzz_001"))


func test_achievement_events_persist_idempotently() -> void:
	var manager: Node = SaveManagerClass.new()
	manager.set("path_override", "user://test_mixing_flavors_savegame.json")
	add_child_autoqfree(manager)
	manager.call("load_game")
	var event := {"type": "round_cleared", "event_id": "test-round-1", "depth": 1, "streak": 1, "mistakes": 0}
	var first: Dictionary = manager.call("record_achievement_event", event)
	var second: Dictionary = manager.call("record_achievement_event", event)
	assert_true(bool(first.get("success", false)))
	assert_true(bool(second.get("success", false)))
	assert_eq(int(manager.call("get_achievement_state").get("attempts", 0)), 1)
	assert_true(manager.call("get_achievement_state").get("unlocked_ids", []).has("first_round_cleared"))


func test_run_history_persists_and_exposes_share_identity() -> void:
	var manager: Node = SaveManagerClass.new()
	manager.set("path_override", "user://test_mixing_flavors_savegame.json")
	add_child_autoqfree(manager)
	manager.call("load_game")
	var summary := {
		"run_id": "unit-run-1",
		"seed": 42,
		"difficulty": "endless",
		"ruleset_version": 1,
		"catalog_version": 1,
		"depth": 3,
		"score": 900,
		"streak": 2,
		"mistakes": 0,
		"completed": false,
		"puzzle_ids": ["a", "b", "c"],
	}
	var result: Dictionary = manager.call("record_run_summary", summary)
	assert_true(bool(result.get("success", false)), str(result.get("message", "")))
	var aggregates: Dictionary = manager.call("get_run_aggregates")
	assert_eq(int(aggregates.get("best_score", 0)), 900)
	var share: Dictionary = manager.call("create_run_share_token", summary)
	assert_true(bool(share.get("success", false)))
	var decoded: Dictionary = manager.call("decode_run_share_token", str(share.get("token", "")))
	assert_eq(int(decoded.get("seed", -1)), 42)


func test_first_gacha_seed_is_initialized_once() -> void:
	var manager: Node = SaveManagerClass.new()
	manager.set("path_override", "user://test_mixing_flavors_savegame.json")
	add_child_autoqfree(manager)
	manager.call("load_game")
	var first_seed: int = int(manager.call("get_or_create_gacha_seed"))
	var second_seed: int = int(manager.call("get_or_create_gacha_seed"))
	assert_gt(first_seed, 0)
	assert_eq(first_seed, second_seed)


func test_daily_results_and_profile_collections_persist() -> void:
	var manager: Node = SaveManagerClass.new()
	manager.set("path_override", "user://test_mixing_flavors_savegame.json")
	add_child_autoqfree(manager)
	manager.call("load_game")
	assert_true(manager.call("save_daily_results", {"2026-09-25": {"completed": true, "best_score": 1234}}))
	manager.call("add_inventory_item", "common_mint", "Common", 1)
	var loaded: Node = SaveManagerClass.new()
	loaded.set("path_override", "user://test_mixing_flavors_savegame.json")
	add_child_autoqfree(loaded)
	var loaded_data: Dictionary = loaded.call("load_game")
	assert_true(loaded_data.get("daily_results", {}).has("2026-09-25"))
	assert_eq(loaded.call("get_themes"), ["Classic"])
	assert_eq(loaded.call("get_trophies"), [])


func test_inventory_upgrade_preserves_one_item() -> void:
	var manager: Node = SaveManagerClass.new()
	manager.set("path_override", "user://test_mixing_flavors_savegame.json")
	add_child_autoqfree(manager)
	manager.call("load_game")
	manager.call("add_inventory_item", "vampire_fangs", "Rare", 1)
	var upgraded: Dictionary = manager.call("add_inventory_item", "vampire_fangs", "Rare", 3)
	assert_eq(int(upgraded.get("mastery", 0)), 3)
	assert_eq((manager.call("get_inventory") as Array).size(), 1)


func test_corrupt_primary_save_recovers_from_backup() -> void:
	var manager: Node = SaveManagerClass.new()
	manager.set("path_override", "user://test_mixing_flavors_savegame.json")
	add_child_autoqfree(manager)
	manager.call("load_game")
	manager.call("add_shards", 37)
	# A second successful write rotates the valid snapshot into the backup.
	manager.call("set_setting", "haptics", false)
	var primary: FileAccess = FileAccess.open("user://test_mixing_flavors_savegame.json", FileAccess.WRITE)
	primary.store_string("{not valid json")
	primary.close()
	var recovered: Node = SaveManagerClass.new()
	recovered.set("path_override", "user://test_mixing_flavors_savegame.json")
	add_child_autoqfree(recovered)
	var data: Dictionary = recovered.call("load_game")
	assert_eq(int((data.get("player_stats", {}) as Dictionary).get("total_shards", 0)), 37)


func test_gacha_result_updates_profile_and_inventory() -> void:
	var manager: Node = SaveManagerClass.new()
	manager.set("path_override", "user://test_mixing_flavors_savegame.json")
	add_child_autoqfree(manager)
	manager.call("load_game")
	manager.call("add_shards", 500)
	var service: Object = GachaServiceClass.new()
	var profile: Dictionary = manager.call("get_gacha_profile")
	var result: Dictionary = service.call("roll", 12345, 1, profile)
	assert_true(bool(result.get("success", false)))
	assert_true(bool(manager.call("apply_gacha_result", result)))
	assert_eq(int((manager.call("get_player_stats") as Dictionary).get("total_shards", 0)), 400)
	assert_eq((manager.call("get_inventory") as Array).size(), 1)


func test_retired_high_contrast_setting_is_dropped_and_cannot_be_restored() -> void:
	var path: String = "user://test_mixing_flavors_savegame.json"
	# A profile written by an older build still advertises the dead control.
	var legacy_file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({
		"version": 3,
		"player_stats": {"total_shards": 12},
		"settings": {"sfx_vol": 0.5, "haptics": false, "high_contrast": true},
	}, "\t"))
	legacy_file.close()

	var manager: Node = SaveManagerClass.new()
	manager.set("path_override", path)
	add_child_autoqfree(manager)
	var loaded: Dictionary = manager.call("load_game")
	var settings: Dictionary = manager.call("get_settings")
	# The retired key is gone from both the fresh defaults and the loaded file.
	assert_false((manager.call("default_data") as Dictionary).get("settings", {}).has("high_contrast"))
	assert_false(settings.has("high_contrast"), "A dead setting must not survive a load")
	# Unrelated data from the same profile still loads, so this is not passing
	# because the settings dictionary failed to merge at all.
	assert_eq(int((loaded.get("player_stats", {}) as Dictionary).get("total_shards", 0)), 12)
	assert_false(bool(settings.get("haptics", true)))
	assert_eq(float(settings.get("sfx_vol", -1.0)), 0.5)
	# The generic setter refuses the retired key instead of storing it again.
	manager.call("set_setting", "high_contrast", true)
	assert_false(manager.call("get_settings").has("high_contrast"))
	# The next commit rewrites the file without the retired key.
	assert_true(bool(manager.call("save_game")))
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(saved is Dictionary, "The rewritten save must still be readable JSON")
	var saved_settings: Dictionary = (saved as Dictionary).get("settings", {}) as Dictionary
	assert_true(saved_settings.has("haptics"), "Rewriting must not empty the settings block")
	assert_false(saved_settings.has("high_contrast"))


func _new_manager(path: String) -> Node:
	var manager: Node = SaveManagerClass.new()
	manager.set("path_override", path)
	add_child_autoqfree(manager)
	manager.call("load_game")
	return manager


func _read_snapshot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _write_snapshot(path: String, snapshot: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot))
	file.close()


# A snapshot is only comparable across storage authorities if it carries a
# monotonic revision. Without one, load had to take the first non-empty source,
# so a stale web copy silently outranked a newer on-disk save.
func test_every_committed_save_advances_the_revision() -> void:
	var path: String = "user://test_mixing_flavors_savegame.json"
	var manager: Node = _new_manager(path)
	var first: int = int(manager.call("get_persistence_status").get("revision", 0))
	manager.call("add_shards", 10)
	var second: int = int(manager.call("get_persistence_status").get("revision", 0))
	manager.call("add_shards", 10)
	var third: int = int(manager.call("get_persistence_status").get("revision", 0))
	assert_gt(second, first, "A durable write must advance the revision")
	assert_gt(third, second, "Each write must advance the revision, not reuse it")
	assert_eq(int(_read_snapshot(path).get("revision", 0)), third, "The revision on disk must match memory")


func test_load_prefers_the_highest_revision_not_the_first_source() -> void:
	var path: String = "user://test_mixing_flavors_savegame.json"
	# Simulate a rolled-back file authority: a newer web copy exists, while the
	# on-disk save is an older revision. The old first-non-empty order could not
	# express this, so the stale copy won.
	var fresh: Dictionary = _read_snapshot(path)
	fresh["player_stats"] = {"total_shards": 999}
	fresh["revision"] = 50
	fresh["updated_at"] = 2000
	var stale: Dictionary = fresh.duplicate(true)
	stale["player_stats"] = {"total_shards": 1}
	stale["revision"] = 7
	stale["updated_at"] = 1000
	_write_snapshot(path, stale)
	_write_snapshot(path + ".backup", stale)
	var manager: Node = _new_manager(path)
	# Point the load at the authoritative "web" copies by seeding the file with
	# the newer revision and deleting nothing else: the file is the only source
	# in a headless run, so assert the revision is adopted and reused.
	assert_eq(int(manager.call("get_persistence_status").get("revision", 0)), 7)
	manager.call("add_shards", 5)
	assert_eq(int(manager.call("get_persistence_status").get("revision", 0)), 8, "The next save must continue from the loaded revision")
	assert_eq(int(manager.call("get_player_stats").get("total_shards", 0)), 6, "Shard state must come from the loaded snapshot")
	assert_eq(int(_read_snapshot(path).get("revision", 0)), 8)


func test_add_shards_does_not_credit_a_reward_it_could_not_store() -> void:
	var path: String = "user://test_mixing_flavors_savegame.json"
	var manager: Node = _new_manager(path)
	manager.call("add_shards", 40)
	# Make the save directory unwritable by pointing the manager at a path whose
	# parent does not exist, so the durable write fails for real.
	manager.set("path_override", "user://missing_dir_xyz/nested/savegame.json")
	var returned: int = int(manager.call("add_shards", 100))
	assert_eq(returned, 40, "A reward that was not stored must not be reported as banked")
	assert_eq(int(manager.call("get_player_stats").get("total_shards", 0)), 40, "In-memory state must roll back with the failed write")
	var status: Dictionary = manager.call("get_persistence_status")
	assert_false(bool(status.get("last_save_succeeded", true)), "The failure must be reported, not swallowed")
	assert_false(str(status.get("last_save_error", "")).is_empty(), "A failure must carry a reason")


func test_record_puzzle_completion_reports_failure_instead_of_a_fake_record() -> void:
	var path: String = "user://test_mixing_flavors_savegame.json"
	var manager: Node = _new_manager(path)
	manager.set("path_override", "user://missing_dir_xyz/nested/savegame.json")
	var record: Dictionary = manager.call("record_puzzle_completion", "puzz_777", 3, 12.0)
	assert_true(record.is_empty(), "An unstored completion must not be returned as recorded")
	assert_false((manager.call("get_completion") as Dictionary).has("puzz_777"))


func test_settings_are_committed_in_one_batched_write() -> void:
	var path: String = "user://test_mixing_flavors_savegame.json"
	var manager: Node = _new_manager(path)
	var start_revision: int = int(manager.call("get_persistence_status").get("revision", 0))
	assert_true(bool(manager.call("set_settings", {
		"haptics": false,
		"reduced_motion": true,
		"sfx_vol": 0.25,
		"bgm_vol": 0.5,
	})))
	var settings: Dictionary = manager.call("get_settings")
	assert_false(bool(settings.get("haptics", true)))
	assert_true(bool(settings.get("reduced_motion", false)))
	assert_eq(float(settings.get("sfx_vol", -1.0)), 0.25)
	assert_eq(float(settings.get("bgm_vol", -1.0)), 0.5)
	# Four values, one durable write: exactly one revision step.
	assert_eq(
		int(manager.call("get_persistence_status").get("revision", 0)),
		start_revision + 1,
		"A batched settings commit must cost exactly one save cycle"
	)


func test_batched_settings_never_resurrect_a_retired_key() -> void:
	var path: String = "user://test_mixing_flavors_savegame.json"
	var manager: Node = _new_manager(path)
	manager.call("set_settings", {"haptics": false, "high_contrast": true})
	var settings: Dictionary = manager.call("get_settings")
	assert_false(settings.has("high_contrast"), "A batch must not bypass the retired-key filter")
	assert_false(bool(settings.get("haptics", true)), "The legitimate keys in the batch still apply")


func test_failed_batched_settings_restore_the_previous_profile() -> void:
	var path: String = "user://test_mixing_flavors_savegame.json"
	var manager: Node = _new_manager(path)
	manager.call("set_settings", {"sfx_vol": 0.75})
	manager.set("path_override", "user://missing_dir_xyz/nested/savegame.json")
	assert_false(bool(manager.call("set_settings", {"sfx_vol": 0.1})))
	assert_eq(float((manager.call("get_settings") as Dictionary).get("sfx_vol", -1.0)), 0.75, "A failed batch must roll back")


func _new_gacha_manager(path: String) -> Node:
	var manager: Node = SaveManagerClass.new()
	manager.set("path_override", path)
	add_child_autoqfree(manager)
	manager.call("load_game")
	return manager


func _roll_for(manager: Node, seed_value: int) -> Dictionary:
	var service: RefCounted = GachaServiceClass.new()
	return service.call("roll", seed_value, GachaServiceClass.CURRENT_CATALOG_VERSION, manager.call("get_gacha_profile"))


# The mint screen told the player "No shards were spent" on a failed write, but
# apply_gacha_result had no rollback: the debited balance and the advanced seed
# stayed in memory, so a retry charged a second time and rolled a different
# result.
func test_failed_mint_rolls_back_the_debit_and_the_seed() -> void:
	var path: String = "user://test_mixing_flavors_savegame.json"
	var manager: Node = _new_gacha_manager(path)
	manager.call("add_shards", 500)
	var shards_before: int = int((manager.call("get_player_stats") as Dictionary).get("total_shards", 0))
	# Create the roll seed first: get_or_create_gacha_seed persists it, so the
	# baseline for the rollback has to be read after that, not before.
	var roll_seed: int = int(manager.call("get_or_create_gacha_seed"))
	var seed_before: int = int((manager.call("get_player_stats") as Dictionary).get("gacha_next_seed", 0))
	var rolls_before: int = int((manager.call("get_player_stats") as Dictionary).get("gacha_roll_count", 0))
	var result: Dictionary = _roll_for(manager, roll_seed)
	# Force the durable write to fail.
	manager.set("path_override", "user://missing_dir_xyz/nested/savegame.json")
	assert_false(bool(manager.call("apply_gacha_result", result)), "a failed write must be reported as failed")
	assert_eq(int((manager.call("get_player_stats") as Dictionary).get("total_shards", 0)), shards_before, "the debit must be rolled back")
	assert_eq(int((manager.call("get_player_stats") as Dictionary).get("gacha_next_seed", 0)), seed_before, "the seed must not advance")
	assert_eq(int((manager.call("get_player_stats") as Dictionary).get("gacha_roll_count", 0)), rolls_before, "the roll must not be counted")
	assert_true((manager.call("get_inventory") as Array).is_empty(), "no item may be granted for an unstored roll")
	var status: Dictionary = manager.call("get_persistence_status")
	assert_false(bool(status.get("last_save_succeeded", true)))


# A replayed result double-incremented the roll count and, because the seed is
# an absolute assignment, rewound the deterministic seed chain.
func test_replaying_the_same_mint_result_is_rejected() -> void:
	var path: String = "user://test_mixing_flavors_savegame.json"
	var manager: Node = _new_gacha_manager(path)
	manager.call("add_shards", 500)
	var seed_value: int = int(manager.call("get_or_create_gacha_seed"))
	var result: Dictionary = _roll_for(manager, seed_value)
	assert_true(bool(manager.call("apply_gacha_result", result)), "the first application must succeed")
	var after_first: Dictionary = manager.call("get_player_stats")
	var count_after_first: int = int(after_first.get("gacha_roll_count", 0))
	var seed_after_first: int = int(after_first.get("gacha_next_seed", 0))
	var shards_after_first: int = int(after_first.get("total_shards", 0))
	assert_false(bool(manager.call("apply_gacha_result", result)), "a replayed result must be rejected")
	var after_replay: Dictionary = manager.call("get_player_stats")
	assert_eq(int(after_replay.get("gacha_roll_count", 0)), count_after_first, "a replay must not double-count the roll")
	assert_eq(int(after_replay.get("gacha_next_seed", 0)), seed_after_first, "a replay must not rewind the seed chain")
	assert_eq(int(after_replay.get("total_shards", 0)), shards_after_first, "a replay must not move the balance")


func test_mint_result_from_an_unsupported_catalog_is_rejected() -> void:
	var path: String = "user://test_mixing_flavors_savegame.json"
	var manager: Node = _new_gacha_manager(path)
	manager.call("add_shards", 500)
	var result: Dictionary = _roll_for(manager, int(manager.call("get_or_create_gacha_seed")))
	result["catalog_version"] = int(GachaServiceClass.CURRENT_CATALOG_VERSION) + 7
	assert_false(bool(manager.call("apply_gacha_result", result)), "a foreign catalog version must be rejected")
	assert_eq(int((manager.call("get_player_stats") as Dictionary).get("gacha_roll_count", 0)), 0)


func test_pity_counters_are_clamped_to_the_service_limits() -> void:
	var path: String = "user://test_mixing_flavors_savegame.json"
	var manager: Node = _new_gacha_manager(path)
	manager.call("add_shards", 500)
	var result: Dictionary = _roll_for(manager, int(manager.call("get_or_create_gacha_seed")))
	# A result claiming absurd pity must be clamped to the service's own limits,
	# not to literals duplicated in the save layer.
	result["pity_after"] = {"epic": 9999, "legendary": 9999}
	assert_true(bool(manager.call("apply_gacha_result", result)))
	var stats: Dictionary = manager.call("get_player_stats")
	assert_lte(int(stats.get("gacha_epic_pity", -1)), int(GachaServiceClass.EPIC_PITY_LIMIT))
	assert_lte(int(stats.get("gacha_legendary_pity", -1)), int(GachaServiceClass.LEGENDARY_PITY_LIMIT))


# The disclosed odds must be the rates the selection actually enforces, and the
# pity guarantee has to be stated: the base table understates the rare rates.
func test_disclosed_odds_match_the_enforced_buckets() -> void:
	var percentages: Dictionary = GachaServiceClass.get_rarity_percentages()
	assert_eq(int(percentages.get("Common", 0)), 60)
	assert_eq(int(percentages.get("Rare", 0)), 25)
	assert_eq(int(percentages.get("Epic", 0)), 12)
	assert_eq(int(percentages.get("Legendary", 0)), 3)
	var total: int = 0
	for rarity: Variant in percentages.keys():
		total += int(percentages[rarity])
	assert_eq(total, 100, "the disclosed rates must sum to 100")
	var disclosure: String = GachaServiceClass.get_odds_disclosure()
	assert_true(disclosure.contains("Base rates"), "the disclosure must not present base rates as the real odds: " + disclosure)
	var pity_disclosure: String = GachaServiceClass.get_pity_disclosure()
	assert_true(pity_disclosure.contains("guaranteed"), "the pity guarantee must be disclosed: " + pity_disclosure)
	assert_true(pity_disclosure.contains("10th"), "the epic pity threshold must be disclosed: " + pity_disclosure)
	assert_true(pity_disclosure.contains("30th"), "the legendary pity threshold must be disclosed: " + pity_disclosure)