extends GutTest

const RunHistoryServiceClass = preload("res://scripts/RunHistoryService.gd")

var service: Object


func before_each() -> void:
	service = RunHistoryServiceClass.new(10)


func test_normalization_and_determinism_do_not_require_a_clock() -> void:
	var first: Dictionary = service.call("record_run", _record("run-a", 42, 900, 7, 4, false, ["p1", "p2"]))
	var second_service: Object = RunHistoryServiceClass.new(10)
	var second: Dictionary = second_service.call("record_run", _record("run-a", 42, 900, 7, 4, false, ["p1", "p2"]))

	assert_true(bool(first.get("success", false)))
	assert_true(bool(second.get("success", false)))
	assert_eq(first.get("record", {}), second.get("record", {}))
	var record: Dictionary = first.get("record", {}) as Dictionary
	assert_eq(str(record.get("run_id", "")), "run-a")
	assert_eq(str(record.get("difficulty", "")), "hard")
	assert_eq(int(record.get("seed", -1)), 42)
	assert_eq(str(record.get("sequence_fingerprint", "")), RunHistoryServiceClass.fingerprint_sequence(["p1", "p2"]))
	assert_false(record.has("timestamp"))
	assert_false(record.has("started_at"))
	assert_false(record.has("completed_at"))


func test_generated_run_id_is_stable_for_the_same_replay_identity() -> void:
	var first: Dictionary = service.call("record_run", _record("", 123, 100, 2, 1, true, ["a", "b"], true))
	var second_service: Object = RunHistoryServiceClass.new(10)
	var second: Dictionary = second_service.call("record_run", _record("", 123, 100, 2, 1, true, ["a", "b"], true))

	assert_true(bool(first.get("success", false)))
	assert_true(bool(second.get("success", false)))
	assert_eq(str(first.get("run_id", "")), str(second.get("run_id", "")))
	assert_true(str(first.get("run_id", "")).begins_with("run_"))


func test_malformed_records_fail_transactionally() -> void:
	var valid: Dictionary = service.call("record_run", _record("valid", 10, 20, 3, 2, true, ["p1"]))
	var before: Dictionary = service.call("export_snapshot")
	assert_true(bool(valid.get("success", false)))

	var invalid_payloads: Array = [
		_record("bad-seed", -1, 20, 3, 2, true, ["p1"]),
		_record("bad-difficulty", 10, 20, 3, 2, true, ["p1"]),
		_record("bad-depth", 10, 20, -3, 2, true, ["p1"]),
		_record("bad-mistakes", 10, 20, 3, 2, true, ["p1"]),
	]
	invalid_payloads[1]["difficulty"] = "impossible"
	invalid_payloads[2]["depth"] = -3
	invalid_payloads[3]["mistakes"] = -2
	var wrong_fingerprint: Dictionary = _record("bad-fingerprint", 10, 20, 3, 2, true, ["p1"])
	wrong_fingerprint["sequence_fingerprint"] = "0".repeat(64)
	invalid_payloads.append(wrong_fingerprint)
	var bad_timestamp: Dictionary = _record("bad-timestamp", 10, 20, 3, 2, true, ["p1"])
	bad_timestamp["timestamp"] = ""
	invalid_payloads.append(bad_timestamp)

	for payload: Dictionary in invalid_payloads:
		var result: Dictionary = service.call("record_run", payload)
		assert_false(bool(result.get("success", true)))
		assert_true(str(result.get("error_code", "")).length() > 0)
	assert_eq(service.call("export_snapshot"), before)
	assert_eq((service.call("get_all_runs") as Array).size(), 1)


func test_idempotent_updates_and_run_id_conflicts_are_explicit() -> void:
	var payload: Dictionary = _record("same-id", 55, 500, 6, 3, true, ["p1", "p2"])
	var first: Dictionary = service.call("record_run", payload)
	var repeated: Dictionary = service.call("record_run", payload)
	var changed: Dictionary = _record("same-id", 55, 501, 6, 3, true, ["p1", "p2"])
	var conflict: Dictionary = service.call("record_run", changed)

	assert_true(bool(first.get("success", false)))
	assert_true(bool(repeated.get("success", false)))
	assert_true(bool(repeated.get("idempotent", false)))
	assert_false(bool(repeated.get("changed", true)))
	assert_false(bool(conflict.get("success", true)))
	assert_eq(str(conflict.get("error_code", "")), "RUN_ID_CONFLICT")
	assert_eq((service.call("get_all_runs") as Array).size(), 1)
	assert_eq(int((service.call("get_run", "same-id") as Dictionary).get("score", 0)), 500)


func test_history_bound_and_eviction_are_deterministic() -> void:
	var bounded: Object = RunHistoryServiceClass.new(2)
	var first: Dictionary = bounded.call("record_run", _record("oldest", 1, 10, 1, 0, false, ["a"]))
	var second: Dictionary = bounded.call("record_run", _record("middle", 2, 20, 2, 1, false, ["b"]))
	var third: Dictionary = bounded.call("record_run", _record("newest", 3, 30, 3, 2, false, ["c"]))

	assert_true(bool(first.get("success", false)))
	assert_true(bool(second.get("success", false)))
	assert_true(bool(third.get("success", false)))
	assert_eq((bounded.call("get_all_runs") as Array).size(), 2)
	assert_eq(str((bounded.call("get_all_runs") as Array)[0].get("run_id", "")), "middle")
	assert_eq(str((bounded.call("get_all_runs") as Array)[1].get("run_id", "")), "newest")
	assert_eq(third.get("evicted_run_ids", []), ["oldest"])
	assert_eq(int((bounded.call("get_aggregates") as Dictionary).get("best_score", 0)), 30)
	var reduced: Dictionary = bounded.call("set_max_history", 1)
	assert_true(bool(reduced.get("success", false)))
	assert_eq((bounded.call("get_all_runs") as Array).size(), 1)
	assert_eq(str((bounded.call("get_all_runs") as Array)[0].get("run_id", "")), "newest")


func test_best_aggregates_reflect_run_metrics() -> void:
	service.call("record_run", _record("low", 1, 100, 2, 1, false, ["a"]))
	service.call("record_run", _record("high", 2, 900, 12, 8, true, ["b", "c"]))
	service.call("record_run", _record("middle", 3, 400, 7, 5, false, ["d"]))
	var aggregates: Dictionary = service.call("get_aggregates")

	assert_eq(int(aggregates.get("total_runs", 0)), 3)
	assert_eq(int(aggregates.get("completed_runs", 0)), 1)
	assert_eq(int(aggregates.get("best_score", 0)), 900)
	assert_eq(int(aggregates.get("best_depth", 0)), 12)
	assert_eq(int(aggregates.get("best_streak", 0)), 8)
	assert_eq(int((aggregates.get("best", {}) as Dictionary).get("score", 0)), 900)


func test_filtering_by_difficulty_daily_and_seed() -> void:
	service.call("record_run", _record("hard-daily", 100, 500, 4, 2, true, ["a"], true))
	var easy_record: Dictionary = _record("easy-normal", 100, 300, 2, 1, false, ["b"])
	easy_record["difficulty"] = "easy"
	service.call("record_run", easy_record)
	service.call("record_run", _record("hard-normal", 200, 700, 8, 4, false, ["c"]))

	assert_eq((service.call("filter_runs", {"difficulty": " HARD "}) as Array).size(), 2)
	assert_eq((service.call("filter_runs", {"daily": true}) as Array).size(), 1)
	assert_eq((service.call("filter_runs", {"seed": 100}) as Array).size(), 2)
	assert_eq((service.call("filter_runs", {"difficulty": "hard", "daily": false, "seed": 200}) as Array).size(), 1)
	assert_eq((service.call("get_runs", "easy", false, 100) as Array).size(), 1)


func test_share_token_round_trip_is_compact_and_tamper_evident() -> void:
	var supported_ruleset: int = int(RunHistoryServiceClass.SUPPORTED_RULESET_VERSION)
	var supported_catalog: int = int(RunHistoryServiceClass.SUPPORTED_CATALOG_VERSION)
	var encoded: Dictionary = service.call("encode_share_token", 987654, " HARD ", supported_ruleset, supported_catalog)
	assert_true(bool(encoded.get("success", false)))
	var token: String = str(encoded.get("token", ""))
	assert_true(token.begins_with("mfh1."))
	assert_true(token.length() < 80)
	var decoded: Dictionary = service.call("decode_share_token", token)
	assert_true(bool(decoded.get("success", false)), str(decoded.get("message", "")))
	assert_eq(int(decoded.get("seed", -1)), 987654)
	assert_eq(str(decoded.get("difficulty", "")), "hard")
	assert_eq(int(decoded.get("ruleset_version", -1)), supported_ruleset)
	assert_eq(int(decoded.get("catalog_version", -1)), supported_catalog)

	var tampered: String = token
	if token.substr(token.length() - 1, 1) == "a":
		tampered = token.substr(0, token.length() - 1) + "b"
	else:
		tampered = token.substr(0, token.length() - 1) + "a"
	var rejected: Dictionary = service.call("decode_share_token", tampered)
	assert_false(bool(rejected.get("success", true)))
	assert_eq(str(rejected.get("error_code", "")), "SHARE_TOKEN_TAMPERED")
	assert_false(str(rejected.get("token", "")).contains("987654.900"))


# A future refactor could hash the raw token text's neighbours instead of the
# parsed identity values and still pass a checksum-only test. Mutate an actual
# payload field and prove the checksum covers it.
func test_share_token_checksum_covers_the_payload_fields_not_just_the_suffix() -> void:
	var supported_ruleset: int = int(RunHistoryServiceClass.SUPPORTED_RULESET_VERSION)
	var supported_catalog: int = int(RunHistoryServiceClass.SUPPORTED_CATALOG_VERSION)
	var encoded: Dictionary = service.call("encode_share_token", 4242, "hard", supported_ruleset, supported_catalog)
	var parts: PackedStringArray = str(encoded.get("token", "")).split(".", true)
	assert_eq(parts.size(), 6)
	# Keep the original checksum and swap the seed: the checksum must no longer match.
	var forged_seed: PackedStringArray = parts.duplicate()
	forged_seed[1] = "4243"
	var forged: String = ".".join(forged_seed)
	var result: Dictionary = service.call("decode_share_token", forged)
	assert_false(bool(result.get("success", true)), "an altered seed must not decode")
	assert_eq(str(result.get("error_code", "")), "SHARE_TOKEN_TAMPERED")
	# Same for the catalog version field.
	var forged_catalog: PackedStringArray = parts.duplicate()
	forged_catalog[4] = str(supported_catalog + 7)
	var catalog_result: Dictionary = service.call("decode_share_token", ".".join(forged_catalog))
	assert_false(bool(catalog_result.get("success", true)), "an altered catalog version must not decode")
	assert_eq(str(catalog_result.get("error_code", "")), "SHARE_TOKEN_TAMPERED")


# A token can be structurally perfect and still name an identity this build does
# not implement. Replaying it under current rules would silently apply this
# build's scoring to a foreign identity.
func test_share_token_from_an_unsupported_version_pair_is_rejected() -> void:
	var future_ruleset: int = int(RunHistoryServiceClass.SUPPORTED_RULESET_VERSION) + 1
	var encoded: Dictionary = service.call("encode_share_token", 5150, "hard", future_ruleset, 99)
	assert_true(bool(encoded.get("success", false)), "encoding an arbitrary version pair is still allowed")
	var decoded: Dictionary = service.call("decode_share_token", str(encoded.get("token", "")))
	assert_false(bool(decoded.get("success", true)), "a foreign version pair must not be replayable")
	assert_eq(str(decoded.get("error_code", "")), "SHARE_TOKEN_VERSION_MISMATCH")


# The daily identity hashes these versions, so a second independent constant
# would let the recorded identity drift away from the catalog actually used.
func test_daily_identity_versions_come_from_the_catalog_owner() -> void:
	var puzzle_manager_class: GDScript = load("res://scripts/PuzzleManager.gd")
	var game_manager_class: GDScript = load("res://scripts/GameManager.gd")
	assert_eq(int(game_manager_class.DAILY_CATALOG_VERSION), int(puzzle_manager_class.CATALOG_VERSION))
	assert_eq(int(game_manager_class.DAILY_RULESET_VERSION), int(puzzle_manager_class.RULESET_VERSION))
	assert_eq(int(RunHistoryServiceClass.SUPPORTED_CATALOG_VERSION), int(puzzle_manager_class.CATALOG_VERSION))
	assert_eq(int(RunHistoryServiceClass.SUPPORTED_RULESET_VERSION), int(puzzle_manager_class.RULESET_VERSION))


func test_snapshot_survives_json_round_trip_and_reload() -> void:
	service.call("record_run", _record("persisted", 777, 1234, 15, 9, true, ["p1", "p2", "p3"]))
	var snapshot: Dictionary = service.call("export_snapshot")
	var json_text: String = JSON.stringify(snapshot)
	var reloaded_service: Object = RunHistoryServiceClass.new(2)
	var loaded: Dictionary = reloaded_service.call("load_snapshot", JSON.parse_string(json_text))
	var restored: Dictionary = reloaded_service.call("get_run", "persisted")
	var repeated: Dictionary = reloaded_service.call("record_run", _record("persisted", 777, 1234, 15, 9, true, ["p1", "p2", "p3"]))

	assert_true(bool(loaded.get("success", false)))
	assert_true(bool(reloaded_service.call("load_snapshot", json_text).get("success", false)))
	assert_eq(str(restored.get("run_id", "")), "persisted")
	assert_eq(int(restored.get("score", 0)), 1234)
	assert_true(bool(repeated.get("idempotent", false)))
	assert_eq((reloaded_service.call("get_all_runs") as Array).size(), 1)
	assert_eq(int((reloaded_service.call("get_aggregates") as Dictionary).get("best_depth", 0)), 15)
	var array_service: Object = RunHistoryServiceClass.new(2)
	var array_loaded: Dictionary = array_service.call("load_snapshot", [_record("array-run", 8, 80, 3, 2, true, ["z"])])
	assert_true(bool(array_loaded.get("success", false)))
	assert_true(array_service.call("has_run", "array-run"))


func test_explicit_timestamps_are_preserved_but_never_invented() -> void:
	var payload: Dictionary = _record("timed", 4, 50, 2, 1, true, ["a"])
	payload["started_at"] = "2026-09-25T12:00:00Z"
	payload["completed_at"] = 1780000000
	var result: Dictionary = service.call("record_run", payload)
	var record: Dictionary = result.get("record", {}) as Dictionary
	assert_eq(str(record.get("started_at", "")), "2026-09-25T12:00:00Z")
	assert_eq(int(record.get("completed_at", -1)), 1780000000)
	assert_false(record.has("timestamp"))


func _record(
	run_id: String,
	seed_value: int,
	score: int,
	depth: int,
	streak: int,
	completed: bool,
	puzzle_ids: Array,
	daily: bool = false
) -> Dictionary:
	var record: Dictionary = {
		"seed": seed_value,
		"difficulty": "hard",
		"ruleset_version": 1,
		"catalog_version": 7,
		"depth": depth,
		"score": score,
		"streak": streak,
		"mistakes": 1,
		"completed": completed,
		"puzzle_ids": puzzle_ids.duplicate(true),
		"is_daily": daily,
	}
	if not run_id.is_empty():
		record["run_id"] = run_id
	return record


# The save layer persists run history as JSON, and a JSON round trip
# materializes every number as a float. daily_id validation used a raw TYPE_INT
# check, so the first daily run a player completed made their whole stored
# history unloadable on the next launch - the run feature died permanently.
func test_daily_run_history_survives_a_json_round_trip() -> void:
	var daily: Dictionary = _record("daily-json", 24680, 500, 5, 2, true, ["p1", "p2", "p3"])
	daily["is_daily"] = true
	daily["daily_id"] = 777777
	daily["daily_date"] = "2026-09-25"
	var recorded: Dictionary = service.call("record_run", daily)
	assert_true(bool(recorded.get("success", false)), str(recorded.get("message", "")))
	var reloaded_service: Object = RunHistoryServiceClass.new(2)
	var loaded: Dictionary = reloaded_service.call("load_snapshot", JSON.parse_string(JSON.stringify(service.call("export_snapshot"))))
	assert_true(bool(loaded.get("success", false)), "a stored daily run must reload: %s" % str(loaded.get("message", "")))
	var stored: Dictionary = reloaded_service.call("get_run", "daily-json")
	assert_false(stored.is_empty(), "the daily run must survive the round trip")
	assert_eq(int(stored.get("daily_id", -1)), 777777, "an integral float daily_id must be accepted")
	assert_eq(str(stored.get("daily_date", "")), "2026-09-25")
	# A fractional value is still not an integer identity.
	var fractional: Dictionary = _record("daily-frac", 1, 1, 1, 1, true, ["p1"])
	fractional["is_daily"] = true
	fractional["daily_id"] = 1.5
	fractional["daily_date"] = "2026-09-25"
	assert_false(bool(service.call("record_run", fractional).get("success", true)), "a fractional daily_id must still be rejected")