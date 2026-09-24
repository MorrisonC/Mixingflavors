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
