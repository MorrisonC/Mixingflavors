extends GutTest

const MainMenuScene: PackedScene = preload("res://scenes/MainMenu.tscn")
const VoxelLogicScene: PackedScene = preload("res://scenes/VoxelLogic.tscn")
const EscapeGauntletScene: PackedScene = preload("res://scenes/EscapeGauntlet.tscn")
const TutorialUIScene: PackedScene = preload("res://scenes/TutorialUI.tscn")
const VictoryScene: PackedScene = preload("res://scenes/victory_screen.tscn")
const ArchiveScene: PackedScene = preload("res://scenes/ArchiveScreen.tscn")


func test_settings_is_a_blocking_focusable_modal() -> void:
	var menu: Control = MainMenuScene.instantiate() as Control
	add_child_autoqfree(menu)
	await get_tree().process_frame

	var panel: Panel = menu.get_node("SettingsPanel") as Panel
	var scrim: ColorRect = menu.get_node("SettingsScrim") as ColorRect
	var close_button: Button = panel.get_node("CloseButton") as Button
	var haptics_check: CheckBox = panel.get_node("VBoxContainer/HapticsCheck") as CheckBox
	assert_not_null(panel)
	assert_not_null(scrim)
	assert_not_null(haptics_check)
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


func test_standalone_puzzle_has_a_retry_game_over_surface() -> void:
	var gameplay: Node = VoxelLogicScene.instantiate()
	add_child_autoqfree(gameplay)
	await get_tree().process_frame
	gameplay.call("_show_standalone_game_over")
	var overlay: Control = gameplay.get_node_or_null("CanvasLayer/StandaloneGameOver") as Control
	assert_not_null(overlay)
	assert_true(overlay.visible)
	assert_not_null(overlay.find_child("RetryButton", true, false))
	assert_not_null(overlay.find_child("LeaveButton", true, false))


func test_gameplay_toolbar_wraps_and_slice_hint_controls_are_touch_sized() -> void:
	var gameplay: Node = VoxelLogicScene.instantiate()
	add_child_autoqfree(gameplay)
	await get_tree().process_frame

	var toolbar: Node = gameplay.get_node("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer")
	assert_true(toolbar is GridContainer)
	assert_true((toolbar as GridContainer).columns >= 1 and (toolbar as GridContainer).columns <= 5)
	for button_name in ["ChiselButton", "MarkButton", "SliceToggleButton", "UndoButton", "HintButton", "ResetViewButton"]:
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


func test_archive_has_scrollable_collection_and_safe_navigation() -> void:
	var archive: Control = ArchiveScene.instantiate() as Control
	add_child_autoqfree(archive)
	await get_tree().process_frame
	var scroll: ScrollContainer = archive.get_node("Margin/VBox/Scroll") as ScrollContainer
	var back: Button = archive.get_node("Margin/VBox/BackButton") as Button
	var mint: Button = archive.get_node("Margin/VBox/MintButton") as Button
	assert_true(scroll is ScrollContainer)
	assert_true(bool(scroll.size_flags_vertical & Control.SIZE_EXPAND))
	assert_true(back.custom_minimum_size.y >= 44.0)
	assert_true(mint.custom_minimum_size.y >= 44.0)
	assert_not_null(archive.get_node_or_null("Margin/VBox/CompletionLabel"))
	assert_not_null(archive.get_node_or_null("Margin/VBox/RatesLabel"))
	assert_not_null(archive.get_node_or_null("Margin/VBox/PityLabel"))
	assert_not_null(archive.get_node_or_null("Margin/VBox/AchievementLabel"))
	assert_not_null(archive.get_node_or_null("Margin/VBox/RecordsLabel"))
	assert_not_null(archive.get_node_or_null("Margin/VBox/ShareButton"))


func test_gauntlet_hud_labels_do_not_overlap() -> void:
	var gauntlet: Node3D = EscapeGauntletScene.instantiate() as Node3D
	add_child_autoqfree(gauntlet)
	await get_tree().process_frame
	gauntlet.call("_apply_responsive_layout")
	var timer: Control = gauntlet.get_node("CanvasLayer/UI/TimerLabel") as Control
	var score: Control = gauntlet.get_node("CanvasLayer/UI/ScoreLabel") as Control
	var bank: Control = gauntlet.get_node("CanvasLayer/UI/BankLabel") as Control
	var health: Control = gauntlet.get_node("CanvasLayer/UI/HealthLabel") as Control
	var round: Control = gauntlet.get_node("CanvasLayer/UI/RoundLabel") as Control
	assert_false(timer.get_global_rect().intersects(score.get_global_rect()))
	assert_false(timer.get_global_rect().intersects(health.get_global_rect()))
	assert_false(timer.get_global_rect().intersects(bank.get_global_rect()))
	assert_false(round.get_global_rect().intersects(score.get_global_rect()))


func test_tutorial_banner_and_victory_actions_are_responsive() -> void:
	var tutorial: CanvasLayer = TutorialUIScene.instantiate() as CanvasLayer
	add_child_autoqfree(tutorial)
	var banner: PanelContainer = tutorial.get_node("MarginContainer/VBoxContainer/BannerPanel") as PanelContainer
	var skip_button: Button = tutorial.get_node("MarginContainer/VBoxContainer/TopRow/SkipButton") as Button
	assert_eq(banner.custom_minimum_size.x, 0.0)
	assert_true(skip_button.custom_minimum_size.y >= 44.0)


func test_guided_tutorial_banner_actually_renders_its_instruction() -> void:
	# Regression: the banner label shipped with max_lines_visible = 0, which
	# clips the label after zero lines. The guided instruction was assigned
	# correctly every step and still never appeared on screen, so "How to Play"
	# looked like it had no instructions at all.
	var tutorial: CanvasLayer = TutorialUIScene.instantiate() as CanvasLayer
	add_child_autoqfree(tutorial)
	await get_tree().process_frame
	var banner_label: Label = tutorial.get_node("MarginContainer/VBoxContainer/BannerPanel/MarginContainer/Row/BannerLabel") as Label
	var step_label: Label = tutorial.get_node("MarginContainer/VBoxContainer/BannerPanel/MarginContainer/Row/StepChip/MarginContainer/StepLabel") as Label
	assert_not_null(banner_label)
	assert_not_null(step_label)
	assert_eq(banner_label.max_lines_visible, -1, "The instruction label must not be clipped to zero lines")
	assert_eq(banner_label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	assert_true(banner_label.clip_contents == false, "The banner must not clip the wrapped instruction")

	var manager := TutorialManager.new()
	manager.name = "TutorialManagerForTest"
	add_child(manager)
	tutorial.call("setup", manager)
	await get_tree().process_frame
	var expected: String = str(manager.step_instructions.get(manager.current_step, ""))
	assert_false(expected.is_empty(), "The first guided step needs instruction copy")
	assert_eq(banner_label.text, expected, "The banner must show the current step's instruction")
	assert_eq(step_label.text, "STEP 1/5")
	manager.queue_free()

	var victory: Control = VictoryScene.instantiate() as Control
	add_child_autoqfree(victory)
	var stats: NonogramStats = NonogramStats.new(65.0, "Endless 1 - Heart", 12345, 2)
	victory.call("initialize", stats)
	var next_button: Button = victory.get_node("Background/PanelContainer/VBoxContainer/NextButton") as Button
	var leave_button: Button = victory.get_node("Background/PanelContainer/VBoxContainer/LeaveButton") as Button
	assert_true(next_button.custom_minimum_size.y >= 44.0)
	assert_true(leave_button.custom_minimum_size.y >= 44.0)


func test_victory_queues_result_until_ready_and_renders_authoritative_fields() -> void:
	var victory: Control = VictoryScene.instantiate() as Control
	add_child_autoqfree(victory)
	victory.call("set", "result_context", "gauntlet")
	victory.call("initialize", {
		"current_level_string": "Round 4 - Neon Gate",
		"time_seconds": 41.0,
		"raw_score": 9876,
		"stars_earned": 3,
		"round": 4,
		"seed": 2468,
		"best_depth": 12,
		"best_score": 15000,
		"streak": 4,
		"difficulty": "endless",
		"share_code": "mfh1.test",
	})
	await get_tree().process_frame
	var header: Label = victory.get_node("Background/PanelContainer/VBoxContainer/HeaderLabel") as Label
	var time_value: Label = victory.get_node("Background/PanelContainer/VBoxContainer/StatsContainer/TimeRow/Value") as Label
	var score_value: Label = victory.get_node("Background/PanelContainer/VBoxContainer/StatsContainer/ScoreRow/Value") as Label
	var stars_value: Label = victory.get_node("Background/PanelContainer/VBoxContainer/StatsContainer/StarsRow/Value") as Label
	var seed_value: Label = victory.get_node("Background/PanelContainer/VBoxContainer/StatsContainer/SeedRow/Value") as Label
	var best_value: Label = victory.get_node("Background/PanelContainer/VBoxContainer/StatsContainer/BestRow/Value") as Label
	assert_eq(header.text, "Round 4 - Neon Gate")
	assert_eq(time_value.text, "00:41")
	assert_eq(score_value.text, "9,876")
	assert_eq(stars_value.text, "3/3")
	assert_eq(seed_value.text, "2468")
	assert_true(best_value.text.contains("12"))
	assert_eq(victory.call("get_result_snapshot").get("score", 0), 9876)
	assert_true((victory.get_node("Background/PanelContainer/VBoxContainer/ActionRow/ReplayButton") as Button).custom_minimum_size.y >= 44.0)


func test_final_gauntlet_result_restores_hidden_parent_hud() -> void:
	var gauntlet: Node3D = EscapeGauntletScene.instantiate() as Node3D
	add_child_autoqfree(gauntlet)
	await get_tree().process_frame
	var parent_ui: Control = gauntlet.get_node("CanvasLayer/UI") as Control
	parent_ui.hide()
	gauntlet.call("_win_gauntlet")
	var game_over: Control = gauntlet.get_node("CanvasLayer/UI/GameOver") as Control
	assert_true(game_over.is_visible_in_tree(), "Terminal result must not be hidden by the reveal HUD state")
	assert_true((game_over.get_node("GameOverPanel/GameOverVBox/GameOverTitle") as Label).text.contains("CLEARED"))
