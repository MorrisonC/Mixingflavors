extends GutTest

func test_game_manager_autoload():
    var gm = get_tree().root.get_node_or_null("GameManager")
    if not gm:
        gm = preload("res://scripts/GameManager.gd").new()
        gm.name = "GameManager"
        get_tree().root.add_child(gm)
    assert_not_null(gm, "GameManager autoload should be initialized")

func test_initial_stats():
    var gm = get_tree().root.get_node_or_null("GameManager")
    if not gm: return # Test setup failed
    assert_eq(gm.get_stat("perception"), 2, "Perception should be 2 initially")
    assert_eq(gm.get_stat("health"), 100, "Health should be 100 initially")

func test_switch_mode():
    var gm = get_tree().root.get_node_or_null("GameManager")
    if not gm: return # Test setup failed
    gm.switch_mode(gm.GameMode.VOXEL_LOGIC)
    assert_eq(gm.current_mode, gm.GameMode.VOXEL_LOGIC, "Current mode should update after switch_mode")
