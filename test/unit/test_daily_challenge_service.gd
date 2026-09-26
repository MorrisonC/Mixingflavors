extends GutTest

const DailyChallengeServiceClass = preload("res://scripts/DailyChallengeService.gd")


class FakeSelector:
	extends RefCounted
	var calls: Array = []

	func select(seed_value: int, depth: int) -> Dictionary:
		calls.append({"seed": seed_value, "depth": depth})
		return {
			"id": "daily_puzzle_%d_%d" % [seed_value % 1000, depth],
			"validated_by_selector": true,
		}


func _new_service() -> Object:
	return DailyChallengeServiceClass.new()


func test_same_day_and_versions_have_stable_identity_and_sequence() -> void:
	var first_selector: FakeSelector = FakeSelector.new()
	var second_selector: FakeSelector = FakeSelector.new()
	var first: Dictionary = _new_service().call(
		"create_daily_challenge",
		"2026-09-25",
		1,
		7,
		Callable(first_selector, "select")
	)
	var second: Dictionary = _new_service().call(
		"create_daily_challenge",
		"2026-09-25",
		1,
		7,
		Callable(second_selector, "select")
	)

	assert_true(bool(first.get("success", false)))
	assert_true(bool(second.get("success", false)))
	assert_eq(int(first.get("daily_id", -1)), int(second.get("daily_id", -2)))
	assert_eq(int(first.get("seed", -1)), int(second.get("seed", -2)))
	assert_gte(int(first.get("daily_id", -1)), 0)
	assert_gte(int(first.get("seed", -1)), 0)
	assert_eq(first.get("puzzle_ids", []), second.get("puzzle_ids", []))
	assert_eq(first.get("sequence_fingerprint", ""), second.get("sequence_fingerprint", ""))
	assert_eq((first.get("puzzle_ids", []) as Array).size(), 31)
	assert_eq(first_selector.calls.size(), 31)
	assert_eq(int(first_selector.calls[0].get("depth", 0)), 1)
	assert_eq(int(first_selector.calls[30].get("depth", 0)), 31)


func test_date_and_ruleset_or_catalog_changes_change_identity() -> void:
	var base: Dictionary = _new_service().call("derive_daily", "2026-09-25", 1, 7)
	var next_date: Dictionary = _new_service().call("derive_daily", "2026-09-26", 1, 7)
	var next_ruleset: Dictionary = _new_service().call("derive_daily", "2026-09-25", 2, 7)
	var next_catalog: Dictionary = _new_service().call("derive_daily", "2026-09-25", 1, 8)

	assert_true(bool(base.get("success", false)))
	assert_true(int(base.get("daily_id", -1)) != int(next_date.get("daily_id", -2)))
	assert_true(int(base.get("seed", -1)) != int(next_date.get("seed", -2)))
	assert_true(int(base.get("daily_id", -1)) != int(next_ruleset.get("daily_id", -2)))
	assert_true(int(base.get("daily_id", -1)) != int(next_catalog.get("daily_id", -2)))
	assert_eq(int(next_date.get("day_index", -1)), int(base.get("day_index", -2)) + 1)


func test_utc_rollover_and_leap_day_are_deterministic() -> void:
	var before_rollover: Dictionary = _new_service().call("derive_daily", "2028-02-28", 3, 2)
	var leap_day: Dictionary = _new_service().call("derive_daily", "2028-02-29", 3, 2)
	var after_rollover: Dictionary = _new_service().call("derive_daily", "2028-03-01", 3, 2)

	assert_true(bool(leap_day.get("success", false)))
	assert_eq(int(leap_day.get("day_index", -1)), int(before_rollover.get("day_index", -2)) + 1)
	assert_eq(int(after_rollover.get("day_index", -1)), int(leap_day.get("day_index", -2)) + 1)
	assert_true(int(leap_day.get("daily_id", -1)) != int(after_rollover.get("daily_id", -2)))


func test_malformed_dates_versions_sequence_and_results_fail_closed() -> void:
	var service: Object = _new_service()
	var invalid_date: Dictionary = service.call("derive_daily", "2026-02-30", 1, 1)
	var invalid_date_shape: Dictionary = service.call("derive_daily", "2026-2-01", 1, 1)
	var invalid_ruleset: Dictionary = service.call("derive_daily", "2026-09-25", -1, 1)
	var invalid_catalog_type: Dictionary = service.call("derive_daily", "2026-09-25", 1, "1")
	var invalid_sequence: Dictionary = service.call(
		"create_daily_challenge",
		"2026-09-25",
		1,
		1,
		Callable(FakeSelector.new(), "select"),
		0
	)
	var invalid_result: Dictionary = service.call(
		"record_result",
		"2026-09-25",
		1,
		1,
		{"completed": true, "score": 100, "depth": 4, "stars": 9}
	)
	var invalid_snapshot: Dictionary = service.call(
		"load_local_results",
		{"results": {"bad": {"completed": true}}}
	)

	assert_eq(str(invalid_date.get("error_code", "")), "INVALID_DATE")
	assert_eq(str(invalid_date_shape.get("error_code", "")), "INVALID_DATE")
	assert_eq(str(invalid_ruleset.get("error_code", "")), "INVALID_RULESET_VERSION")
	assert_eq(str(invalid_catalog_type.get("error_code", "")), "INVALID_CATALOG_VERSION")
	assert_eq(str(invalid_sequence.get("error_code", "")), "INVALID_SEQUENCE_LENGTH")
	assert_eq(str(invalid_result.get("error_code", "")), "INVALID_RESULT")
	assert_eq(str(invalid_snapshot.get("error_code", "")), "INVALID_RESULT_RECORD")
	assert_false(bool(invalid_date.get("success", true)))
	assert_false(bool(invalid_result.get("success", true)))
	assert_false(bool(invalid_snapshot.get("success", true)))


func test_result_updates_are_idempotent_and_preserve_best_values() -> void:
	var service: Object = _new_service()
	var result_data: Dictionary = {
		"completed": true,
		"score": 900,
		"depth": 12,
		"stars": 3,
	}
	var first: Dictionary = service.call("record_result", "2026-09-25", 1, 7, result_data)
	var repeated: Dictionary = service.call("record_result", "2026-09-25", 1, 7, result_data)
	var lower_result: Dictionary = service.call(
		"record_result",
		"2026-09-25",
		1,
		7,
		{"completed": false, "score": 100, "depth": 3, "stars": 1}
	)

	var record: Dictionary = first.get("record", {})
	assert_true(bool(first.get("changed", false)))
	assert_true(bool(repeated.get("idempotent", false)))
	assert_false(bool(repeated.get("changed", true)))
	assert_eq(int(record.get("attempts", 0)), 1)
	assert_eq(int((repeated.get("record", {}) as Dictionary).get("attempts", 0)), 1)
	assert_eq(int((lower_result.get("record", {}) as Dictionary).get("attempts", 0)), 2)
	assert_eq(int((lower_result.get("record", {}) as Dictionary).get("best_score", 0)), 900)
	assert_eq(int((lower_result.get("record", {}) as Dictionary).get("best_depth", 0)), 12)
	assert_eq(int((lower_result.get("record", {}) as Dictionary).get("stars", 0)), 3)
	assert_true(bool((lower_result.get("record", {}) as Dictionary).get("completed", false)))


func test_local_result_snapshot_survives_service_reload() -> void:
	var first_service: Object = _new_service()
	var recorded: Dictionary = first_service.call(
		"record_result",
		"2026-09-25",
		1,
		7,
		{"completed": true, "score": 500, "depth": 8, "stars": 2}
	)
	assert_true(bool(recorded.get("success", false)))
	var snapshot: Dictionary = first_service.call("get_local_results")
	var persisted_snapshot: Variant = JSON.parse_string(JSON.stringify(snapshot))

	var restored_service: Object = _new_service()
	var loaded: Dictionary = restored_service.call("load_local_results", persisted_snapshot)
	var restored: Dictionary = restored_service.call("get_result", "2026-09-25", 1, 7)
	var repeated_after_reload: Dictionary = restored_service.call(
		"record_result",
		"2026-09-25",
		1,
		7,
		{"completed": true, "score": 500, "depth": 8, "stars": 2}
	)

	assert_true(bool(loaded.get("success", false)))
	assert_true(bool(restored.get("found", false)))
	assert_true(bool(repeated_after_reload.get("idempotent", false)))
	assert_eq(int((restored.get("record", {}) as Dictionary).get("attempts", 0)), 1)
	assert_eq(int((repeated_after_reload.get("record", {}) as Dictionary).get("attempts", 0)), 1)
	assert_eq(int((restored.get("record", {}) as Dictionary).get("best_score", 0)), 500)


func test_catch_up_includes_prior_dates_without_punishment() -> void:
	var service: Object = _new_service()
	var selector: FakeSelector = FakeSelector.new()
	var current_result: Dictionary = service.call(
		"record_result",
		"2026-09-25",
		1,
		7,
		{"completed": true, "score": 100, "depth": 3, "stars": 1}
	)
	assert_true(bool(current_result.get("success", false)))

	var catch_up: Dictionary = service.call(
		"get_catch_up_challenges",
		"2026-09-25",
		1,
		7,
		Callable(selector, "select"),
		3,
		true
	)
	assert_true(bool(catch_up.get("success", false)))
	var challenges: Array = catch_up.get("challenges", [])
	assert_eq(challenges.size(), 3)
	assert_eq(str((challenges[0] as Dictionary).get("utc_date", "")), "2026-09-23")
	assert_true(bool((challenges[0] as Dictionary).get("is_catch_up", false)))
	assert_true(bool((challenges[0] as Dictionary).get("pending", true)))
	var current_challenge: Dictionary = challenges[2] as Dictionary
	var current_record: Dictionary = current_challenge.get("record", {}) as Dictionary
	assert_true(bool(current_challenge.get("completed", false)))
	assert_eq(int(current_record.get("attempts", 0)), 1)
