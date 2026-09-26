extends Node
class_name GauntletManagerService

## Pure, deterministic rules for the endless voxel gauntlet.
## The scene owns presentation and input; this service owns run state so the
## timer, streak, banking, and difficulty rules can be tested without a viewport.

signal run_started(difficulty: String, depth: int, puzzle: Dictionary)
signal round_started(depth: int, tier: String, puzzle: Dictionary, time_limit: float)
signal timer_changed(time_left: float)
signal mistake_registered(mistakes: int, time_left: float)
signal round_cleared(result: Dictionary)
signal run_failed(reason: String)

const STARTING_TIME: float = 120.0
const MAX_BANKED_TIME: float = 300.0
const MISTAKE_PENALTY: float = 15.0
const MAX_STREAK_MULTIPLIER: int = 10
const BASE_CLEAR_BONUS: float = 10.0
const DIFFICULTY_CURVE: GDScript = preload("res://scripts/DifficultyCurve.gd")

var puzzle_manager: Node = null
var difficulty: String = "endless"
var run_seed: int = 0
var depth: int = 1
var streak: int = 0
var mistakes: int = 0
var round_mistakes: int = 0
var score: int = 0
var time_left: float = STARTING_TIME
var round_time_limit: float = STARTING_TIME
var banked_time: float = 0.0
var active_puzzle: Dictionary = {}
var is_running: bool = false


func _ready() -> void:
	if puzzle_manager == null:
		puzzle_manager = get_node_or_null("/root/PuzzleManager") as Node


func set_puzzle_manager(manager: Node) -> void:
	puzzle_manager = manager


func start_run(selected_difficulty: String = "endless", seed_value: int = 0) -> void:
	difficulty = selected_difficulty.strip_edges().to_lower()
	if difficulty not in ["easy", "medium", "hard", "endless"]:
		difficulty = "endless"
	run_seed = seed_value
	depth = 1
	streak = 0
	mistakes = 0
	round_mistakes = 0
	score = 0
	banked_time = 0.0
	is_running = true
	var first_puzzle: Dictionary = _puzzle_for_current_round()
	run_started.emit(difficulty, depth, first_puzzle.duplicate(true))
	_begin_round(first_puzzle)


func stop_run() -> void:
	is_running = false
	active_puzzle = {}


func tick(delta: float) -> bool:
	if not is_running:
		return false
	time_left = maxf(0.0, time_left - maxf(0.0, delta))
	timer_changed.emit(time_left)
	if is_zero_approx(time_left):
		_fail("time_expired")
	return true


func register_mistake() -> Dictionary:
	if not is_running:
		return {}
	mistakes += 1
	round_mistakes += 1
	streak = 0
	time_left = maxf(0.0, time_left - MISTAKE_PENALTY)
	mistake_registered.emit(mistakes, time_left)
	if is_zero_approx(time_left):
		_fail("mistakes")
	return get_state()


func preview_clear(par_time_seconds: float) -> Dictionary:
	## Returns the exact score/depth projection that register_clear() will
	## commit for the current round. This is presentation-only: it never
	## mutates the run, so the result card can be truthful before Continue.
	if not is_running:
		return {}
	return _calculate_clear_result(par_time_seconds)


func register_clear(par_time_seconds: float) -> Dictionary:
	if not is_running:
		return {}
	var result: Dictionary = _calculate_clear_result(par_time_seconds)
	if result.is_empty():
		return {}
	banked_time = float(result.get("banked_time", banked_time))
	score = int(result.get("score", score))
	streak = int(result.get("streak", streak))
	depth = int(result.get("next_depth", depth + 1))
	round_cleared.emit(result)
	_begin_round()
	return result


func _calculate_clear_result(par_time_seconds: float) -> Dictionary:
	var clear_time: float = maxf(0.0, round_time_limit - time_left)
	var par_time: float = maxf(0.0, par_time_seconds)
	var streak_multiplier: int = clampi(streak + 1, 1, MAX_STREAK_MULTIPLIER)
	var speed_bonus: float = maxf(0.0, par_time - clear_time) * 0.5
	var bonus: float = (BASE_CLEAR_BONUS + speed_bonus) * float(streak_multiplier)
	var next_banked_time: float = minf(MAX_BANKED_TIME, banked_time + bonus)
	var next_score: int = score + 100 + depth * 10 + int(bonus * 10.0)
	return {
		"depth": depth,
		"next_depth": depth + 1,
		"clear_time": clear_time,
		"par_time": par_time,
		"bonus": bonus,
		"banked_time": next_banked_time,
		"score": next_score,
		"streak": streak_multiplier,
		"mistakes": mistakes,
		"time_left": time_left,
		"round_time_limit": round_time_limit,
	}


func refund_round_mistake() -> bool:
	if not is_running or round_mistakes <= 0:
		return false
	round_mistakes -= 1
	return true


func fail_run(reason: String = "manual") -> void:
	if is_running:
		_fail(reason)


func get_state() -> Dictionary:
	return {
		"difficulty": difficulty,
		"run_seed": run_seed,
		"depth": depth,
		"streak": streak,
		"mistakes": mistakes,
		"round_mistakes": round_mistakes,
		"score": score,
		"time_left": time_left,
		"round_time_limit": round_time_limit,
		"banked_time": banked_time,
		"is_running": is_running,
		"active_puzzle": active_puzzle.duplicate(true),
	}


func _begin_round(puzzle_override: Dictionary = {}) -> void:
	if not is_running:
		return
	# The GDD defines a fixed 120-second round clock. Banked time is a capped
	# progression resource used for rewards, not a way to extend later rounds.
	round_time_limit = STARTING_TIME
	time_left = STARTING_TIME
	round_mistakes = 0
	var tier: String = get_tier_for_depth(depth)
	active_puzzle = puzzle_override.duplicate(true) if not puzzle_override.is_empty() else _puzzle_for_current_round()
	round_started.emit(depth, tier, active_puzzle.duplicate(true), round_time_limit)
	timer_changed.emit(time_left)


func _puzzle_for_current_round() -> Dictionary:
	if puzzle_manager == null:
		puzzle_manager = get_node_or_null("/root/PuzzleManager") as Node
	if puzzle_manager != null and puzzle_manager.has_method("get_puzzle_for_round"):
		var selected: Variant = puzzle_manager.call("get_puzzle_for_round", run_seed, depth, difficulty)
		if selected is Dictionary and not (selected as Dictionary).is_empty():
			return (selected as Dictionary).duplicate(true)
	return {}


func get_tier_for_depth(current_depth: int) -> String:
	return DIFFICULTY_CURVE.get_tier_for_depth(current_depth, difficulty)


func _fail(reason: String) -> void:
	if not is_running:
		return
	is_running = false
	active_puzzle = {}
	run_failed.emit(reason)
