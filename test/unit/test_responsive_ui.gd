extends GutTest

const MainMenuScene: PackedScene = preload("res://scenes/MainMenu.tscn")
const VoxelLogicScene: PackedScene = preload("res://scenes/VoxelLogic.tscn")
const EscapeGauntletScene: PackedScene = preload("res://scenes/EscapeGauntlet.tscn")
const TutorialUIScene: PackedScene = preload("res://scenes/TutorialUI.tscn")
const VictoryScene: PackedScene = preload("res://scenes/victory_screen.tscn")


func test_settings_is_a_blocking_focusable_modal() -> void:
	var menu: Control = MainMenuScene.instantiate() as Control
	add_child_autoqfree(menu)
	await get_tree().process_frame

	var panel: Panel = menu.get_node("SettingsPanel") as Panel
	var scrim: ColorRect = menu.get_node("SettingsScrim") as ColorRect
	var close_button: Button = panel.get_node("CloseButton") as Button
	assert_not_null(panel)
	assert_not_null(scrim)
	assert_true(close_button.custom_minimum_size.y >= 44.0)

	menu.call("_on_settings_pressed")
	await get_tree().process_frame
	assert_true(panel.visible)
	assert_true(scrim.visible)
	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_STOP)

	var cancel_event: InputEventAction = InputEventAction.new()
	cancel_event.action = "ui_cancel"
	cancel_event.pressed = true
	menu.call("_unhandled_input", cancel_event)
	assert_false(panel.visible)
	assert_false(scrim.visible)


func test_gameplay_toolbar_wraps_and_slice_hint_controls_are_touch_sized() -> void:
	var gameplay: Node = VoxelLogicScene.instantiate()
	add_child_autoqfree(gameplay)
	await get_tree().process_frame

	var toolbar: Node = gameplay.get_node("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer")
	assert_true(toolbar is GridContainer)
	assert_true((toolbar as GridContainer).columns <= 2)
	for button_name in ["ChiselButton", "MarkButton", "SliceToggleButton", "UndoButton", "HintButton"]:
		var button: Button = gameplay.get_node("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/" + button_name) as Button
		assert_true(button.custom_minimum_size.y >= 44.0)
	var slider: HSlider = gameplay.get_node("CanvasLayer/Control/MarginContainer/VBoxContainer/SliceControls/SliderY") as HSlider
	assert_true(slider.custom_minimum_size.y >= 44.0)
	var slice_toggle: Button = gameplay.get_node("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/SliceToggleButton") as Button
	slice_toggle.emit_signal("pressed")
	var slice_controls: Control = gameplay.get_node("CanvasLayer/Control/MarginContainer/VBoxContainer/SliceControls") as Control
	assert_true(slice_controls.visible)


func test_gauntlet_uses_one_hud_and_has_safe_game_over_card() -> void:
	var gauntlet: Node3D = EscapeGauntletScene.instantiate() as Node3D
	add_child_autoqfree(gauntlet)
	await get_tree().process_frame

	var active_puzzle: Node = gauntlet.get("active_puzzle") as Node
	var child_ui: Control = active_puzzle.get_node("CanvasLayer/Control") as Control
	var child_top_row: Control = child_ui.get_node("MarginContainer/TopRowContainer") as Control
	assert_false(child_top_row.visible, "The child puzzle HUD must not compete with the gauntlet HUD")
	assert_not_null(gauntlet.get_node_or_null("CanvasLayer/UI/HealthLabel"))
	assert_not_null(gauntlet.get_node_or_null("CanvasLayer/UI/ScoreLabel"))

	var quit_button: Button = gauntlet.get_node("CanvasLayer/UI/QuitButton") as Button
	quit_button.emit_signal("pressed")
	var confirm: Control = gauntlet.get_node("CanvasLayer/UI/ConfirmDialog") as Control
	assert_true(confirm.visible)
	assert_eq(confirm.mouse_filter, Control.MOUSE_FILTER_STOP)
	gauntlet.call("_on_no_pressed")
	assert_false(confirm.visible)

	gauntlet.call("_fail_gauntlet")
	var game_over: Control = gauntlet.get_node("CanvasLayer/UI/GameOver") as Control
	assert_true(game_over.visible)
	var retry: Button = game_over.get_node("GameOverPanel/GameOverVBox/GameOverButtons/RetryButton") as Button
	var leave: Button = game_over.get_node("GameOverPanel/GameOverVBox/GameOverButtons/LeaveButton") as Button
	assert_true(retry.custom_minimum_size.y >= 44.0)
	assert_true(leave.custom_minimum_size.y >= 44.0)


func test_tutorial_banner_and_victory_actions_are_responsive() -> void:
	var tutorial: CanvasLayer = TutorialUIScene.instantiate() as CanvasLayer
	add_child_autoqfree(tutorial)
	var banner: PanelContainer = tutorial.get_node("MarginContainer/VBoxContainer/BannerPanel") as PanelContainer
	var skip_button: Button = tutorial.get_node("MarginContainer/VBoxContainer/TopRow/SkipButton") as Button
	assert_eq(banner.custom_minimum_size.x, 0.0)
	assert_true(skip_button.custom_minimum_size.y >= 44.0)

	var victory: Control = VictoryScene.instantiate() as Control
	add_child_autoqfree(victory)
	var stats: NonogramStats = NonogramStats.new(65.0, "Endless 1 - Heart", 12345, 2)
	victory.call("initialize", stats)
	var next_button: Button = victory.get_node("Background/PanelContainer/VBoxContainer/NextButton") as Button
	var leave_button: Button = victory.get_node("Background/PanelContainer/VBoxContainer/LeaveButton") as Button
	assert_true(next_button.custom_minimum_size.y >= 44.0)
	assert_true(leave_button.custom_minimum_size.y >= 44.0)
