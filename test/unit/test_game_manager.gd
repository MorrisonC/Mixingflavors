extends GutTest

const GameManagerClass = preload("res://scripts/GameManager.gd")
var game_manager

func before_each():
    game_manager = GameManagerClass.new()
    add_child(game_manager)

func after_each():
    game_manager.queue_free()

func test_game_manager_autoload():
    assert_not_null(game_manager, "GameManager instance should be initialized")

func test_initial_stats():
    assert_eq(game_manager.get_stat("perception"), 2, "Perception should be 2 initially")
    assert_eq(game_manager.get_stat("health"), 100, "Health should be 100 initially")

func test_switch_mode():
    game_manager.switch_mode(game_manager.GameMode.VOXEL_LOGIC)
    assert_eq(game_manager.current_mode, game_manager.GameMode.VOXEL_LOGIC, "Current mode should update after switch_mode")
