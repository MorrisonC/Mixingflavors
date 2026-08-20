extends GutTest

const GameManagerClass = preload("res://scripts/GameManager.gd")

var game_manager

func before_each():
	var gm = get_tree().root.get_node_or_null("GameManager")
	if not gm:
		gm = GameManagerClass.new()
		gm.name = "GameManager"
		get_tree().root.add_child(gm)
	game_manager = gm

func after_each():
	pass

func test_game_mode_flow_sequence():
	assert_not_null(game_manager, "GameManager autoload must exist")

	# 1. Main Menu
	game_manager.switch_mode(GameManagerClass.GameMode.MAIN_MENU)
	assert_eq(game_manager.current_mode, GameManagerClass.GameMode.MAIN_MENU, "Current mode should be MAIN_MENU")

	# 2. Level Select
	game_manager.switch_mode(GameManagerClass.GameMode.PUZZLE_SELECTION)
	assert_eq(game_manager.current_mode, GameManagerClass.GameMode.PUZZLE_SELECTION, "Current mode should be PUZZLE_SELECTION")

	# 3. Escape Gauntlet Game Mode
	game_manager.switch_mode(GameManagerClass.GameMode.ESCAPE_GAUNTLET)
	assert_eq(game_manager.current_mode, GameManagerClass.GameMode.ESCAPE_GAUNTLET, "Current mode should be ESCAPE_GAUNTLET")
