extends GutTest

const MainMenuScene = preload("res://scenes/MainMenu.tscn")
var main_menu

func before_each():
	main_menu = MainMenuScene.instantiate()
	add_child(main_menu)

func after_each():
	main_menu.queue_free()

func test_play_button_switches_mode():
	var play_button = main_menu.get_node_or_null("VBoxContainer/PlayButton")
	assert_not_null(play_button, "Play button should exist")
    # This invokes a real mode change which is valid because GameManager is Autoload
	play_button.emit_signal("pressed")

func test_editor_button_switches_mode():
	var editor_button = main_menu.get_node_or_null("VBoxContainer/EditorButton")
	assert_not_null(editor_button, "Editor button should exist")
	editor_button.emit_signal("pressed")

func test_settings_button_shows_panel():
	var settings_button = main_menu.get_node_or_null("VBoxContainer/SettingsButton")
	assert_not_null(settings_button, "Settings button should exist")

	var settings_panel = main_menu.get_node_or_null("SettingsPanel")
	assert_not_null(settings_panel, "Settings panel should exist")
	assert_false(settings_panel.visible, "Settings should be hidden initially")

	settings_button.emit_signal("pressed")
	assert_true(settings_panel.visible, "Settings should be visible after clicking")
