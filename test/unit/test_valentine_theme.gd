extends GutTest

const GameManagerClass = preload("res://scripts/GameManager.gd")
var game_manager: Node

func before_each():
	game_manager = GameManagerClass.new()
	get_tree().root.add_child(game_manager)

func after_each():
	game_manager.queue_free()

func test_valentine_theme_toggle():
	assert_false(game_manager._valentine_theme_active, "Theme should default to false")

	game_manager.set_valentine_theme(true)
	assert_true(game_manager._valentine_theme_active, "Theme should be updated to true")

	game_manager.set_valentine_theme(false)
	assert_false(game_manager._valentine_theme_active, "Theme should be updated to false")
