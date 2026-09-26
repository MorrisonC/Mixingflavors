extends GutTest

const GameManagerClass = preload("res://scripts/GameManager.gd")

var game_manager: Node

func before_each() -> void:
	game_manager = GameManagerClass.new()
	add_child_autoqfree(game_manager)

func test_game_manager_autoload() -> void:
	assert_not_null(game_manager)

func test_initial_stats() -> void:
	assert_eq(game_manager.get_stat("perception"), 2)
	assert_eq(game_manager.get_stat("health"), 100)

func test_switch_mode() -> void:
	game_manager.switch_mode(game_manager.GameMode.VOXEL_LOGIC)
	assert_eq(game_manager.current_mode, game_manager.GameMode.VOXEL_LOGIC)


func test_daily_challenge_uses_explicit_seed_and_versioned_payload() -> void:
	var result: Dictionary = game_manager.begin_daily_challenge()
	assert_true(bool(result.get("success", false)))
	assert_eq(game_manager.current_mode, game_manager.GameMode.ESCAPE_GAUNTLET)
	assert_true(bool(game_manager.get("mode_payload").get("daily_challenge", false)))
	assert_gte(int(game_manager.get("selected_run_seed")), 0)
	assert_eq(int(game_manager.get("mode_payload").get("daily_ruleset_version", 0)), 1)
