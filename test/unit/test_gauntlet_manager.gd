extends GutTest

const GauntletManagerClass = preload("res://scripts/GauntletManager.gd")
const PuzzleManagerClass = preload("res://scripts/PuzzleManager.gd")


func _make_manager() -> Node:
	var puzzle_manager: Node = PuzzleManagerClass.new()
	add_child_autoqfree(puzzle_manager)
	var gauntlet: Node = GauntletManagerClass.new()
	add_child_autoqfree(gauntlet)
	gauntlet.call("set_puzzle_manager", puzzle_manager)
	return gauntlet


func test_start_run_uses_120_second_bank() -> void:
	var gauntlet: Node = _make_manager()
	gauntlet.call("start_run", "endless", 9)
	assert_true(bool(gauntlet.get("is_running")))
	assert_eq(float(gauntlet.get("time_left")), 120.0)
	assert_eq(float(gauntlet.get("round_time_limit")), 120.0)
	assert_eq(int(gauntlet.get("depth")), 1)


func test_mistake_applies_gdd_penalty() -> void:
	var gauntlet: Node = _make_manager()
	gauntlet.call("start_run", "medium", 2)
	gauntlet.call("register_mistake")
	assert_eq(float(gauntlet.get("time_left")), 105.0)
	assert_eq(int(gauntlet.get("streak")), 0)


func test_clear_rewards_and_advances_depth() -> void:
	var gauntlet: Node = _make_manager()
	gauntlet.call("start_run", "easy", 4)
	var result: Dictionary = gauntlet.call("register_clear", 60.0)
	assert_false(result.is_empty())
	assert_eq(int(gauntlet.get("depth")), 2)
	assert_gt(float(gauntlet.get("banked_time")), 0.0)
	assert_gt(int(gauntlet.get("score")), 0)


func test_expiry_stops_run() -> void:
	var gauntlet: Node = _make_manager()
	gauntlet.call("start_run", "hard", 8)
	gauntlet.call("tick", 121.0)
	assert_false(bool(gauntlet.get("is_running")))
	assert_eq(float(gauntlet.get("time_left")), 0.0)


func test_preview_clear_matches_committed_result_without_mutating_state() -> void:
	var gauntlet: Node = _make_manager()
	gauntlet.call("start_run", "endless", 1234)
	gauntlet.set("time_left", 72.0)
	var preview: Dictionary = gauntlet.call("preview_clear", 120.0)
	var state_before: Dictionary = gauntlet.call("get_state")
	assert_false(preview.is_empty())
	assert_eq(int(gauntlet.get("depth")), int(state_before.get("depth", 0)))
	assert_eq(int(gauntlet.get("score")), int(state_before.get("score", 0)))
	var committed: Dictionary = gauntlet.call("register_clear", 120.0)
	assert_eq(int(preview.get("score", -1)), int(committed.get("score", -2)))
	assert_eq(int(preview.get("next_depth", -1)), int(committed.get("next_depth", -2)))
	assert_eq(float(preview.get("banked_time", -1.0)), float(committed.get("banked_time", -2.0)))


func test_round_mistake_refund_supports_combo_heal() -> void:
	var gauntlet: Node = _make_manager()
	gauntlet.call("start_run", "endless", 77)
	gauntlet.call("register_mistake")
	assert_true(bool(gauntlet.call("refund_round_mistake")))
	assert_eq(int(gauntlet.get("round_mistakes")), 0)
	assert_eq(int(gauntlet.get("mistakes")), 1)


func test_round_mistakes_reset_without_losing_run_total() -> void:
	var gauntlet: Node = _make_manager()
	gauntlet.call("start_run", "endless", 55)
	gauntlet.call("register_mistake")
	assert_eq(int(gauntlet.get("mistakes")), 1)
	assert_eq(int(gauntlet.get("round_mistakes")), 1)
	gauntlet.call("register_clear", 60.0)
	assert_eq(int(gauntlet.get("mistakes")), 1)
	assert_eq(int(gauntlet.get("round_mistakes")), 0)


func test_register_clear_on_a_stopped_run_is_rejected_without_mutating_state() -> void:
	# EscapeGauntlet reads an empty register_clear result as "the service refused
	# the clear" and fails the run, so the service must keep returning {} rather
	# than a projection it never committed.
	var gauntlet: Node = _make_manager()
	gauntlet.call("start_run", "endless", 21)
	gauntlet.call("stop_run")
	var state_before: Dictionary = gauntlet.call("get_state")
	var result: Dictionary = gauntlet.call("register_clear", 60.0)
	assert_true(result.is_empty())
	assert_eq(int(gauntlet.get("depth")), int(state_before.get("depth", -1)))
	assert_eq(int(gauntlet.get("score")), int(state_before.get("score", -1)))
	assert_eq(float(gauntlet.get("banked_time")), float(state_before.get("banked_time", -1.0)))
	assert_false(bool(gauntlet.get("is_running")))
