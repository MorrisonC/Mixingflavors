extends GutTest

func test_game_manager_autoload():
    assert_not_null(GameManager, "GameManager autoload should be initialized")

func test_initial_stats():
    assert_eq(GameManager.get_stat("perception"), 2, "Perception should be 2 initially")
    assert_eq(GameManager.get_stat("health"), 100, "Health should be 100 initially")

func test_switch_mode():
    GameManager.switch_mode(GameManager.GameMode.VOXEL_LOGIC)
    assert_eq(GameManager.current_mode, GameManager.GameMode.VOXEL_LOGIC, "Current mode should update after switch_mode")
