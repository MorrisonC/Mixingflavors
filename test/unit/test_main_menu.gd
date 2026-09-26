extends GutTest

const MainMenuScene = preload("res://scenes/MainMenu.tscn")
const MainMenuScript = preload("res://scripts/MainMenu.gd")

var main_menu

func before_each():
	main_menu = MainMenuScene.instantiate()
	add_child(main_menu)

func after_each():
	main_menu.queue_free()
	await get_tree().process_frame

func test_play_button_switches_mode():
	var play_button = main_menu.get_node_or_null("VBoxContainer/PlayButton")
	assert_not_null(play_button, "Play button should exist")
    # This invokes a real mode change which is valid because GameManager is Autoload
	play_button.emit_signal("pressed")

func test_editor_is_not_part_of_shipping_menu() -> void:
	await get_tree().process_frame
	assert_null(main_menu.get_node_or_null("VBoxContainer/EditorButton"))


func test_menu_backdrop_is_not_a_flat_wash() -> void:
	# The starting screen used to stack a 90%-opaque near-white panel on top of
	# the panorama, which reduced the whole menu to one flat gray value.
	var panorama := main_menu.get_node_or_null("Panorama") as TextureRect
	var scrim := main_menu.get_node_or_null("Background") as TextureRect
	assert_not_null(panorama)
	assert_not_null(scrim)
	assert_eq(panorama.modulate.a, 1.0, "The panorama must render at full opacity")
	assert_false(scrim.modulate.a >= 0.9 and scrim.texture == null, "The scrim must be a gradient, not an opaque fill")


func test_tutorial_entry_point_opens_written_instructions() -> void:
	var tutorial_button = main_menu.get_node_or_null("VBoxContainer/TutorialButton")
	assert_not_null(tutorial_button)
	var modal = main_menu.get_node_or_null("HowToPlayModal")
	assert_not_null(modal)
	assert_false(modal.visible, "How to Play must start closed")

	tutorial_button.emit_signal("pressed")
	await get_tree().process_frame
	assert_true(modal.visible, "How to Play must show the written rules")
	# The button no longer drops straight into a puzzle, so the mode must still
	# be the menu until the player explicitly starts the guided practice.
	var game_manager = get_tree().root.get_node_or_null("GameManager")
	assert_false(game_manager.current_mode == game_manager.GameMode.VOXEL_LOGIC)


func test_how_to_play_lists_every_rule_before_the_practice_starts() -> void:
	var steps = main_menu.get_node_or_null("HowToPlayModal/Panel/Margin/VBoxContainer/Scroll/Steps")
	assert_not_null(steps)
	await get_tree().process_frame
	# One goal card plus one card per rule.
	assert_eq(steps.get_child_count(), 7)
	var text := _collect_text(steps)
	for expected in ["The goal", "Hammer", "Mark", "Slice", "Undo", "Hint", "Reset View", "HP"]:
		assert_true(text.contains(expected), "How to Play should explain '%s'" % expected)


func test_how_to_play_starts_the_guided_practice_on_request() -> void:
	main_menu.call("_on_tutorial_pressed")
	await get_tree().process_frame
	var modal = main_menu.get_node_or_null("HowToPlayModal")
	var start_button = main_menu.get_node_or_null("HowToPlayModal/Panel/Margin/VBoxContainer/ActionRow/StartPracticeButton")
	assert_not_null(start_button)
	assert_true(start_button.custom_minimum_size.y >= 44.0, "Practice action must stay a touch-sized target")
	start_button.emit_signal("pressed")
	await get_tree().process_frame
	assert_false(modal.visible, "The rules must close once the practice starts")
	var game_manager = get_tree().root.get_node_or_null("GameManager")
	assert_true(game_manager.current_mode == game_manager.GameMode.VOXEL_LOGIC)
	assert_true(bool(game_manager.mode_payload.get("tutorial", false)))


func test_how_to_play_back_closes_without_leaving_the_menu() -> void:
	var game_manager = get_tree().root.get_node_or_null("GameManager")
	main_menu.call("_on_tutorial_pressed")
	await get_tree().process_frame
	var mode_before: int = int(game_manager.current_mode)
	var back_button = main_menu.get_node_or_null("HowToPlayModal/Panel/Margin/VBoxContainer/ActionRow/BackButton")
	assert_not_null(back_button)
	assert_true(back_button.custom_minimum_size.y >= 44.0)
	back_button.emit_signal("pressed")
	await get_tree().process_frame
	assert_false(main_menu.get_node_or_null("HowToPlayModal").visible)
	assert_eq(int(game_manager.current_mode), mode_before, "Dismissing the rules must not start a puzzle")


func test_how_to_play_is_a_blocking_focusable_modal() -> void:
	main_menu.call("_on_tutorial_pressed")
	await get_tree().process_frame
	var modal = main_menu.get_node_or_null("HowToPlayModal")
	var scrim = main_menu.get_node_or_null("HowToPlayModal/HowToPlayScrim")
	assert_true(scrim.visible)
	assert_eq(modal.mouse_filter, Control.MOUSE_FILTER_STOP)
	# The menu behind the rules must not be tappable while it is open.
	var play_button = main_menu.get_node_or_null("VBoxContainer/PlayButton")
	assert_true(play_button.disabled)
	main_menu.call("_hide_how_to_play")
	await get_tree().process_frame
	assert_false(play_button.disabled)


func test_how_to_play_copy_is_complete() -> void:
	assert_eq(MainMenuScript.HOW_TO_PLAY_STEPS.size(), 6)
	for step in MainMenuScript.HOW_TO_PLAY_STEPS:
		assert_false(str(step["heading"]).strip_edges().is_empty(), "Every rule needs a heading")
		assert_gt(str(step["body"]).length(), 40, "Every rule needs an explanation the player can act on")


func _collect_text(node: Node) -> String:
	var text: String = ""
	if node is Label:
		text += (node as Label).text + "\n"
	for child in node.get_children():
		text += _collect_text(child)
	return text


func test_settings_button_shows_panel():
	var settings_button = main_menu.get_node_or_null("VBoxContainer/SettingsButton")
	assert_not_null(settings_button, "Settings button should exist")

	var settings_panel = main_menu.get_node_or_null("SettingsPanel")
	assert_not_null(settings_panel, "Settings panel should exist")
	assert_false(settings_panel.visible, "Settings should be hidden initially")

	settings_button.emit_signal("pressed")
	assert_true(settings_panel.visible, "Settings should be visible after clicking")
