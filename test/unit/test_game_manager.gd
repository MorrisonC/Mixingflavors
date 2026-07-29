extends GutTest

const GameManagerClass = preload("res://scripts/GameManager.gd")
var game_manager_node

func before_each():
    game_manager_node = GameManagerClass.new()

func test_game_manager_autoload():
    assert_not_null(game_manager_node, "GameManager autoload should be initialized")

func test_initial_stats():
    assert_eq(game_manager_node.get_stat("perception"), 2, "Perception should be 2 initially")
    assert_eq(game_manager_node.get_stat("health"), 100, "Health should be 100 initially")

func test_switch_mode():
    game_manager_node.switch_mode(GameManagerClass.GameMode.VOXEL_LOGIC)
    assert_eq(game_manager_node.current_mode, GameManagerClass.GameMode.VOXEL_LOGIC, "Current mode should update after switch_mode")

func after_each():
    game_manager_node.free()
