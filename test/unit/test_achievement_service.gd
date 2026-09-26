extends GutTest

const AchievementServiceClass = preload("res://scripts/AchievementService.gd")


func _new_service() -> Object:
	return AchievementServiceClass.new()


func test_definitions_are_unique_versioned_and_luck_free() -> void:
	var definitions: Array = AchievementServiceClass.get_definitions()
	assert_gte(definitions.size(), 10)
	var ids: Dictionary = {}
	for definition_value: Variant in definitions:
		var definition: Dictionary = definition_value as Dictionary
		var achievement_id: String = str(definition.get("id", ""))
		assert_false(achievement_id.is_empty())
		assert_false(ids.has(achievement_id))
		ids[achievement_id] = true
		assert_gte(int(definition.get("version", 0)), 1)
		assert_false(str(definition.get("description", "")).is_empty())
		assert_false(str(definition.get("category", "")).is_empty())
		assert_false(str(definition.get("progress_metric", "")).is_empty())
		assert_gte(int(definition.get("target", 0)), 1)
		assert_false(str(definition.get("unlock_predicate", "")).is_empty())
		assert_false(bool(definition.get("luck_dependent", true)))
		assert_true(AchievementServiceClass.is_luck_independent_definition(definition))
	assert_true(bool(AchievementServiceClass.validate_definition_catalog().get("success", false)))
	assert_false(AchievementServiceClass.has_gacha_luck_dependency())


func test_progress_increments_and_ordinary_play_unlocks() -> void:
	var service: Object = _new_service()
	var first_round: Dictionary = service.call(
		"process_event",
		{
			"type": "round_cleared",
			"event_id": "round-1",
			"depth": 1,
			"streak": 1,
			"mistakes": 0,
		}
	)
	assert_true(bool(first_round.get("success", false)))
	assert_true(bool(first_round.get("changed", false)))
	assert_true((first_round.get("unlocked_ids", []) as Array).has("first_round_cleared"))
	assert_true((first_round.get("unlocked_ids", []) as Array).has("flawless_round"))
	assert_eq(int((service.call("get_achievement_state", "first_round_cleared") as Dictionary).get("progress", 0)), 1)

	var deep_run: Dictionary = service.call(
		"process_event",
		{
			"type": "run_completed",
			"event_id": "run-1",
			"depth": 5,
			"streak": 5,
			"mistakes": 0,
		}
	)
	assert_true(bool(deep_run.get("success", false)))
	assert_true((deep_run.get("unlocked_ids", []) as Array).has("depth_five"))
	assert_true((deep_run.get("unlocked_ids", []) as Array).has("streak_five"))
	assert_true((deep_run.get("unlocked_ids", []) as Array).has("flawless_run"))
	assert_eq(int((service.call("get_achievement_state", "depth_five") as Dictionary).get("progress", 0)), 5)
	assert_eq(int((service.call("get_achievement_state", "flawless_round") as Dictionary).get("progress", 0)), 1)
	assert_gte(int((service.call("get_state") as Dictionary).get("attempts", 0)), 2)


func test_unlock_is_idempotent_for_replayed_event_id() -> void:
	var service: Object = _new_service()
	var event: Dictionary = {
		"type": "round_cleared",
		"event_id": "stable-round",
		"depth": 1,
		"streak": 1,
		"mistakes": 0,
	}
	var first: Dictionary = service.call("process_event", event)
	var state_after_first: String = JSON.stringify(service.call("get_state"))
	var replay: Dictionary = service.call("process_event", event)

	assert_true(bool(first.get("changed", false)))
	assert_true(bool(replay.get("success", false)))
	assert_true(bool(replay.get("idempotent", false)))
	assert_false(bool(replay.get("changed", true)))
	assert_eq((replay.get("unlocked_ids", []) as Array).size(), 0)
	assert_eq(JSON.stringify(service.call("get_state")), state_after_first)
	assert_eq(int((service.call("get_achievement_state", "first_round_cleared") as Dictionary).get("unlock_count", 0)), 1)

	var conflict_before: String = state_after_first
	var conflict: Dictionary = service.call(
		"process_event",
		{
			"type": "round_cleared",
			"event_id": "stable-round",
			"depth": 2,
			"streak": 2,
			"mistakes": 0,
		}
	)
	assert_false(bool(conflict.get("success", true)))
	assert_eq(JSON.stringify(service.call("get_state")), conflict_before)


func test_malformed_events_fail_transactionally() -> void:
	var service: Object = _new_service()
	service.call("process_event", {"type": "round_cleared", "event_id": "valid", "depth": 1})
	var before: String = JSON.stringify(service.call("get_state"))
	var invalid_events: Array = [
		"not a dictionary",
		{},
		{"type": "unknown_action"},
		{"type": "round_cleared", "amount": -1},
		{"type": "round_cleared", "depth": 0},
		{"type": "round_cleared", "streak": "five"},
		{"type": "metric", "metric": "gacha_roll", "amount": 1},
		{"type": "gacha_roll_completed", "rarity": "Legendary"},
		{"type": "compendium_completed", "completed_count": 2, "total_count": 0},
	]
	for invalid_event: Variant in invalid_events:
		var result: Dictionary = service.call("process_event", invalid_event)
		assert_false(bool(result.get("success", true)), "Malformed event should fail: %s" % str(invalid_event))
		assert_eq(JSON.stringify(service.call("get_state")), before)


func test_json_persistence_reload_and_legacy_migration() -> void:
	var first: Object = _new_service()
	first.call("process_event", {"type": "round_cleared", "event_id": "persist-round", "depth": 3, "streak": 2, "mistakes": 0})
	first.call("process_event", {"type": "run_completed", "event_id": "persist-run", "depth": 4, "streak": 2, "mistakes": 1})
	first.call("process_event", {"type": "compendium_puzzle_cleared", "event_id": "persist-puzzle", "puzzle_id": "puzz_001"})
	var completed: Dictionary = first.call(
		"process_event",
		{"type": "compendium_completed", "event_id": "persist-complete", "completed_count": 12, "total_count": 12}
	)
	assert_true((completed.get("unlocked_ids", []) as Array).has("compendium_complete"))
	assert_true((completed.get("unlocked_ids", []) as Array).has("compendium_explorer"))
	first.call("process_event", {"type": "archive_opened", "event_id": "persist-archive"})
	first.call("process_event", {"type": "gacha_disclosure_viewed", "event_id": "persist-disclosure"})
	var canonical_snapshot: String = JSON.stringify(first.call("get_state"))
	var snapshot: Variant = JSON.parse_string(canonical_snapshot)
	var restored: Object = _new_service()
	var load_result: Dictionary = restored.call("load_state", snapshot)
	assert_true(bool(load_result.get("success", false)))
	assert_eq(JSON.stringify(restored.call("get_state")), canonical_snapshot)
	assert_eq(int((restored.call("get_metrics") as Dictionary).get("runs_completed", 0)), 1)
	var replay: Dictionary = restored.call(
		"process_event",
		{"type": "round_cleared", "event_id": "persist-round", "depth": 3, "streak": 2, "mistakes": 0}
	)
	assert_true(bool(replay.get("idempotent", false)))

	var migrated: Object = _new_service()
	var migration: Dictionary = migrated.call(
		"load_state",
		{
			"version": 0,
			"progress": {"rounds_cleared": 10},
			"unlocked": {"ten_rounds_cleared": true},
		}
	)
	assert_true(bool(migration.get("success", false)))
	assert_true(bool(migration.get("migrated", false)))
	assert_eq(int((migrated.call("get_achievement_state", "ten_rounds_cleared") as Dictionary).get("progress", 0)), 10)
	assert_true(bool((migrated.call("get_achievement_state", "ten_rounds_cleared") as Dictionary).get("unlocked", false)))

	var malformed_state: Dictionary = first.call("get_state")
	malformed_state["achievements"]["first_round_cleared"]["attempts"] = "not an integer"
	var before_failed_load: String = JSON.stringify(first.call("get_state"))
	var failed_load: Dictionary = first.call("load_state", malformed_state)
	assert_false(bool(failed_load.get("success", true)))
	assert_eq(JSON.stringify(first.call("get_state")), before_failed_load)


func test_gacha_policy_allows_disclosure_without_roll_luck() -> void:
	var service: Object = _new_service()
	var rejected_roll: Dictionary = service.call(
		"process_event",
		{"type": "gacha_roll", "rarity": "Legendary", "item_id": "legendary_test"}
	)
	assert_false(bool(rejected_roll.get("success", true)))
	var disclosure: Dictionary = service.call(
		"process_event",
		{"type": "gacha_disclosure_viewed", "event_id": "read-rates"}
	)
	assert_true(bool(disclosure.get("success", false)))
	assert_true((disclosure.get("unlocked_ids", []) as Array).has("gacha_disclosure"))
	var state: Dictionary = service.call("get_state")
	assert_eq(int((state.get("metrics", {}) as Dictionary).get("gacha_disclosure_actions", 0)), 1)
	assert_false((state.get("metrics", {}) as Dictionary).has("gacha_rolls"))


func test_reset_requires_explicit_confirmation() -> void:
	var service: Object = _new_service()
	service.call("process_event", {"type": "round_cleared", "event_id": "before-reset", "depth": 1})
	var before: String = JSON.stringify(service.call("get_state"))
	var refused: Dictionary = service.call("reset")
	assert_false(bool(refused.get("success", true)))
	assert_eq(JSON.stringify(service.call("get_state")), before)
	var refused_again: Dictionary = service.call("reset_local_state", false)
	assert_false(bool(refused_again.get("success", true)))
	assert_eq(JSON.stringify(service.call("get_state")), before)

	var reset_result: Dictionary = service.call("reset_local_state", true)
	assert_true(bool(reset_result.get("success", false)))
	var state: Dictionary = service.call("get_state")
	assert_eq(int(state.get("attempts", -1)), 0)
	assert_eq((state.get("unlocked_ids", []) as Array).size(), 0)
	assert_false(bool((state.get("achievements", {}) as Dictionary).get("first_round_cleared", {}).get("unlocked", true)))
