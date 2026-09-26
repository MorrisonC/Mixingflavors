extends GutTest

const EscapeGauntletScene: PackedScene = preload("res://scenes/EscapeGauntlet.tscn")
const GameManagerClass = preload("res://scripts/GameManager.gd")
const SaveManagerClass = preload("res://scripts/SaveManager.gd")
const RunHistoryServiceClass = preload("res://scripts/RunHistoryService.gd")
const DailyChallengeServiceClass = preload("res://scripts/DailyChallengeService.gd")

var gauntlet: Node3D

func before_each() -> void:
	if not get_tree().root.has_node("GameManager"):
		var game_manager := GameManagerClass.new()
		game_manager.name = "GameManager"
		get_tree().root.add_child(game_manager)
	get_tree().root.get_node("GameManager").set("current_mode", GameManagerClass.GameMode.MAIN_MENU)
	gauntlet = EscapeGauntletScene.instantiate() as Node3D
	add_child_autoqfree(gauntlet)
	# The GameManager autoload is shared across tests in a run, so a previous
	# test's mode payload can leave the gauntlet flagged as a daily. Reset the
	# daily identity explicitly so each test states its own intent.
	gauntlet.set("is_daily_challenge", false)
	gauntlet.set("daily_id", -1)
	gauntlet.set("daily_date", "")
	gauntlet.set("_daily_result_recorded", false)

func after_each() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func test_initialization() -> void:
	assert_not_null(gauntlet.active_puzzle)
	assert_eq(gauntlet.current_round, 1)
	assert_gt(gauntlet.time_left, 0.0)
	var puzzle_data: Dictionary = gauntlet.active_puzzle.get("custom_puzzle_data")
	assert_true(puzzle_data.has("target_voxels"))
	assert_true(puzzle_data.has("clues"))
	assert_eq(gauntlet.active_puzzle.grid_size, Vector3i(puzzle_data["dims"][0], puzzle_data["dims"][1], puzzle_data["dims"][2]))

func test_round_progression() -> void:
	gauntlet.call("_on_puzzle_solved")
	await get_tree().process_frame
	assert_eq(gauntlet.current_round, 2)
	assert_gt(gauntlet.time_left, 0.0)

func test_boss_round() -> void:
	gauntlet.set("current_round", 9)
	gauntlet.call("_on_puzzle_solved")
	await get_tree().process_frame
	assert_eq(gauntlet.current_round, 10)
	assert_eq(gauntlet.current_wave_type, "boss")

func test_mistake_failure_opens_game_over_without_silent_mode_switch() -> void:
	# Lives are a per-round resource; three separate mistakes end this round.
	gauntlet.call("_on_mistake_made", 1)
	gauntlet.call("_on_mistake_made", 2)
	gauntlet.call("_on_mistake_made", 3)
	assert_true(gauntlet.is_game_over)
	assert_true((gauntlet.get_node("CanvasLayer/UI/GameOver") as Control).visible)
	assert_eq(get_tree().root.get_node("GameManager").current_mode, GameManagerClass.GameMode.MAIN_MENU)

func _total_shards() -> int:
	var save_manager: Node = get_tree().root.get_node_or_null("SaveManager")
	return int((save_manager.call("get_player_stats") as Dictionary).get("total_shards", 0))


## Run history is written through the durable save path, so assert against a
## freshly loaded copy instead of the live autoload cache. Reading the cache can
## pass even when nothing was persisted.
func _reload_and_get_latest_run(save_manager: Node) -> Dictionary:
	var reloaded: Node = SaveManagerClass.new()
	add_child_autoqfree(reloaded)
	reloaded.call("load_game")
	var latest: Dictionary = reloaded.call("get_latest_run")
	return latest

func test_empty_clear_result_fails_run_instead_of_paying_and_restarting() -> void:
	# A stopped run makes GauntletManager.register_clear return {}. Only a
	# non-empty result advances the run, so the scene must not fall through to
	# the shard payout and the next round on an empty result.
	var gauntlet_service: Node = gauntlet.gauntlet_manager
	assert_not_null(gauntlet_service)
	var save_manager: Node = get_tree().root.get_node_or_null("SaveManager")
	assert_not_null(save_manager, "the shard payout can only be observed through the SaveManager autoload")
	gauntlet_service.call("stop_run")
	var shards_before: int = _total_shards()
	var puzzle_ids_before: int = gauntlet.run_puzzle_ids.size()
	var puzzle_instance_before: int = gauntlet.active_puzzle.get_instance_id()
	gauntlet.call("_on_puzzle_solved")
	await get_tree().process_frame
	assert_true(gauntlet.is_game_over)
	assert_true((gauntlet.get_node("CanvasLayer/UI/GameOver") as Control).visible)
	assert_eq(gauntlet.current_round, 1)
	assert_eq(gauntlet.run_puzzle_ids.size(), puzzle_ids_before)
	assert_eq(gauntlet.active_puzzle.get_instance_id(), puzzle_instance_before)
	assert_eq(_total_shards(), shards_before)

func test_pending_victory_card_always_leaves_the_leave_button_reachable() -> void:
	# The child builds its result card roughly two seconds after the solve. If it
	# never shows up, the parent HUD - which carries Leave/Quit - has to come back
	# instead of stranding a touch player behind _awaiting_victory_next.
	var parent_hud: Control = gauntlet.get_node("CanvasLayer/UI") as Control
	# The grace is shortened for the test; the shipped default is far longer.
	gauntlet.set("victory_card_grace_seconds", 0.25)
	gauntlet.call("_on_child_puzzle_solved")
	assert_true(gauntlet._awaiting_victory_next)
	assert_false(parent_hud.visible)
	await get_tree().create_timer(0.4).timeout
	assert_true(parent_hud.visible)
	assert_true(gauntlet._awaiting_victory_next)
	assert_false(gauntlet.is_round_active)
	# Resuming from the quit dialog must not hide the HUD a second time.
	gauntlet.call("_set_modal_open", true)
	gauntlet.call("_on_no_pressed")
	assert_true(parent_hud.visible)

func test_abandoned_victory_wait_restores_round_controls() -> void:
	# Losing the pending card mid-reveal has to end the wait the same way. The
	# grace is long enough that only the abandoned wait can restore the HUD.
	var parent_hud: Control = gauntlet.get_node("CanvasLayer/UI") as Control
	gauntlet.set("victory_card_grace_seconds", 600.0)
	gauntlet.call("_on_child_puzzle_solved")
	assert_true(gauntlet._awaiting_victory_next)
	assert_false(parent_hud.visible)
	var pending_puzzle: Node = gauntlet.active_puzzle
	pending_puzzle.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(parent_hud.visible)
	assert_true(gauntlet._awaiting_victory_next)


# The round payout is only honest if the player is told when the reward could
# not be stored. SaveManager.add_shards now rolls back and reports the balance
# that actually survived, so a failed write must not read as a banked reward.
func test_round_reward_is_not_announced_when_it_could_not_be_stored() -> void:
	var save_manager: Node = get_tree().root.get_node_or_null("SaveManager")
	assert_not_null(save_manager, "the reward path is observed through the SaveManager autoload")
	var original_path: String = str(save_manager.get("path_override"))
	# Force every durable write to fail by pointing the profile at a directory
	# that does not exist, then confirm the balance does not move.
	save_manager.set("path_override", "user://missing_dir_xyz/nested/savegame.json")
	var shards_before: int = _total_shards()
	var returned: int = int(save_manager.call("add_shards", 100))
	assert_eq(returned, shards_before, "an unstored reward must not be reported as banked")
	assert_eq(_total_shards(), shards_before, "the profile must roll back with the failed write")
	var status: Dictionary = save_manager.call("get_persistence_status")
	assert_false(bool(status.get("last_save_succeeded", true)), "the failure must be visible to callers")
	save_manager.set("path_override", original_path)


func test_batched_settings_commit_costs_one_save_cycle() -> void:
	var save_manager: Node = get_tree().root.get_node_or_null("SaveManager")
	assert_not_null(save_manager)
	var start_revision: int = int((save_manager.call("get_persistence_status") as Dictionary).get("revision", 0))
	assert_true(bool(save_manager.call("set_settings", {
		"haptics": false,
		"reduced_motion": true,
		"sfx_vol": 0.3,
	})))
	var end_revision: int = int((save_manager.call("get_persistence_status") as Dictionary).get("revision", 0))
	assert_eq(end_revision, start_revision + 1, "four settings must not cost four save cycles")
	save_manager.call("set_settings", {"haptics": true, "reduced_motion": false, "sfx_vol": 1.0})


# RunHistoryService defines sequence_fingerprint as the hash of THIS run's
# puzzle ids. The scene used to supply the catalog hash instead, which can never
# match, so every record_run was rejected and run history was silently empty.
func test_run_summary_is_accepted_with_the_run_sequence_fingerprint() -> void:
	var gauntlet_service: Node = gauntlet.gauntlet_manager
	var save_manager: Node = get_tree().root.get_node_or_null("SaveManager")
	assert_not_null(gauntlet_service)
	assert_not_null(save_manager, "run history is observed through the SaveManager autoload")
	gauntlet.set("run_puzzle_ids", PackedStringArray(["puzz_001", "puzz_002", "puzz_003"]))
	gauntlet.set("run_seed", 987654)
	gauntlet.set("score", 4200)
	gauntlet.set("current_round", 3)
	gauntlet.set("is_daily_challenge", false)
	assert_false(bool(gauntlet.get("is_daily_challenge")), "the non-daily case must not be flagged as a daily")
	assert_eq(int(gauntlet.get("daily_id")), -1, "the non-daily case must not carry a daily identity")
	var ids_at_call: Array = (gauntlet.get("run_puzzle_ids") as Array).duplicate()
	var result: Dictionary = gauntlet.call("_record_run_summary", true)
	assert_true(bool(result.get("success", false)), "the run summary must be accepted: %s" % str(result.get("message", "")))
	var latest: Dictionary = _reload_and_get_latest_run(save_manager)
	assert_false(latest.is_empty(), "a finished run must be readable from history")
	assert_eq(int(latest.get("seed", -1)), 987654)
	assert_eq(int(latest.get("score", -1)), 4200)
	var stored_ids: Array = latest.get("puzzle_ids", []) as Array
	assert_false(stored_ids.is_empty(), "history must keep the run's own puzzle ids")
	assert_eq(stored_ids, ids_at_call, "history must record exactly the ids the run played")
	assert_eq(
		str(latest.get("sequence_fingerprint", "")),
		RunHistoryServiceClass.fingerprint_sequence(ids_at_call),
		"the stored fingerprint must cover the run's own sequence, not the catalog"
	)


func test_run_summary_records_the_daily_identity_and_a_timestamp() -> void:
	var gauntlet_service: Node = gauntlet.gauntlet_manager
	var save_manager: Node = get_tree().root.get_node_or_null("SaveManager")
	assert_not_null(save_manager)
	gauntlet.set("run_puzzle_ids", PackedStringArray(["puzz_010"]))
	gauntlet.set("run_seed", 24680)
	gauntlet.set("is_daily_challenge", true)
	gauntlet.set("daily_id", 777777)
	gauntlet.set("daily_date", "2026-09-25")
	var before: int = int(Time.get_unix_time_from_system())
	var result: Dictionary = gauntlet.call("_record_run_summary", true)
	assert_true(bool(result.get("success", false)), str(result.get("message", "")))
	var latest: Dictionary = _reload_and_get_latest_run(save_manager)
	assert_true(bool(latest.get("is_daily", false)), "a daily run must be marked as one")
	assert_eq(int(latest.get("daily_id", -1)), 777777, "history must attribute the daily to its identity")
	assert_eq(str(latest.get("daily_date", "")), "2026-09-25", "history must attribute the daily to its date")
	assert_gte(int(latest.get("completed_at", 0)), before, "a stored run must carry when it happened")
	gauntlet.set("is_daily_challenge", false)


# Retrying a finished daily must re-issue the daily rather than replaying the
# identical sequence as a plain endless run under the daily's own seed.
func test_retrying_a_daily_reissues_the_daily_instead_of_a_plain_run() -> void:
	var game_manager: Node = get_tree().root.get_node_or_null("GameManager")
	assert_not_null(game_manager)
	gauntlet.set("is_daily_challenge", true)
	gauntlet.set("daily_date", "2026-09-25")
	gauntlet.set("daily_id", 13579)
	gauntlet.set("run_seed", 13579)
	gauntlet.retry_victory_seed()
	var payload: Variant = game_manager.get("mode_payload")
	assert_true(payload is Dictionary, "retry must switch modes with a payload")
	var daily_payload: Dictionary = payload as Dictionary
	assert_true(bool(daily_payload.get("daily_challenge", false)), "a daily retry must stay a daily")
	# A daily retry re-issues *today's* daily, so the payload date comes from the
	# clock rather than from whatever date the finished run carried. Asserting a
	# literal calendar date here made this test pass on exactly one day.
	assert_eq(str(daily_payload.get("daily_date", "")), _current_utc_date())
	gauntlet.set("is_daily_challenge", false)
	gauntlet.set("daily_date", "")


# Stars used to be derived from mirrored HP, which combo healing can restore, so
# a run that made mistakes could still score 3 stars and the 2-star band was
# unreachable. The authoritative mistake counter must drive it.
func test_daily_stars_come_from_the_authoritative_mistake_counter() -> void:
	var gauntlet_service: Node = gauntlet.gauntlet_manager
	assert_not_null(gauntlet_service)
	var save_manager: Node = get_tree().root.get_node_or_null("SaveManager")
	assert_not_null(save_manager)
	gauntlet.set("is_daily_challenge", true)
	gauntlet.set("daily_date", "2026-09-25")
	gauntlet._daily_result_recorded = false
	gauntlet.set("run_puzzle_ids", PackedStringArray(["puzz_001", "puzz_002"]))
	gauntlet.set("score", 1500)
	# Health looks untouched (combo healed) but the run made two mistakes.
	gauntlet.set("current_health", gauntlet.max_mistakes)
	gauntlet_service.set("mistakes", 2)
	var record: Dictionary = gauntlet.call("_record_daily_result", true)
	assert_false(record.is_empty(), "the daily result must be recorded")
	assert_eq(int(record.get("stars", -1)), 1, "two mistakes must not read as a perfect run")
	var reloaded: Node = SaveManagerClass.new()
	add_child_autoqfree(reloaded)
	reloaded.call("load_game")
	# Daily results are stored under their derived daily id, inside a wrapper
	# object, so assert through the service rather than by date text.
	var snapshot: Dictionary = reloaded.call("get_daily_results")
	assert_false(snapshot.is_empty(), "the daily result must be persisted, not just returned")
	var daily_service: RefCounted = DailyChallengeServiceClass.new()
	var loaded_results: Dictionary = daily_service.call("load_local_results", snapshot)
	assert_true(bool(loaded_results.get("success", false)), str(loaded_results.get("message", "")))
	var stored: Dictionary = daily_service.call(
		"get_local_result",
		"2026-09-25",
		int(GameManagerClass.DAILY_RULESET_VERSION),
		int(GameManagerClass.DAILY_CATALOG_VERSION)
	)
	assert_false(stored.is_empty(), "the persisted daily record must be readable through the service")
	assert_eq(int(stored.get("stars", -1)), 1, "two mistakes must not read as a perfect run")
	assert_true(bool(stored.get("completed", false)), "a completed daily must stay marked completed")
	gauntlet.set("is_daily_challenge", false)
	gauntlet.set("daily_date", "")


## The same UTC derivation GameManager.get_utc_date_string uses.
func _current_utc_date() -> String:
	var utc: Dictionary = Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02d" % [int(utc.get("year", 1970)), int(utc.get("month", 1)), int(utc.get("day", 1))]