extends Control

const GameManagerClass = preload("res://scripts/GameManager.gd")
const TUTORIAL_PUZZLE_PATH: String = "res://data/puzzles/tutorial_star.json"

## Written rules for the "How to Play" screen. The guided practice only ever
## showed one short line at a time inside the puzzle HUD, which the puzzle's own
## top bar covered, so a new player had no written reference for the objective,
## the cost of a wrong hammer, or what the slicer was for.
const HOW_TO_PLAY_GOAL_TITLE: String = "The goal"
const HOW_TO_PLAY_GOAL_BODY: String = "Remove every block that does not belong to the sculpture. Whatever is left standing when the last wrong block is gone is the reveal — and the round is won."
const HOW_TO_PLAY_STEPS: Array = [
	{
		"heading": "Read the clues",
		"body": "The numbers painted on each face count how many blocks must stay in that line. A 0 means the whole line is empty. A red ? means the line cannot be read yet.",
	},
	{
		"heading": "Hammer — remove what is empty",
		"body": "Tap a block to chisel it away. Only hammer what the clues prove is empty: chiselling a block that belongs to the sculpture costs HP.",
	},
	{
		"heading": "Mark — flag what must stay",
		"body": "Marking is free, so flag every block you have already deduced before you cut. Marked blocks glow and are never destroyed by a hammer.",
	},
	{
		"heading": "Slice — see inside the cube",
		"body": "The layer slicer shaves the cube away one plane at a time. Intersect two clues from different faces to find blocks that are buried in the middle.",
	},
	{
		"heading": "Drag to orbit",
		"body": "Drag anywhere on the board to spin the sculpture, and pinch or scroll to zoom. Reset View returns you to the readable three-quarter angle.",
	},
	{
		"heading": "Undo and Hint",
		"body": "Undo reverses your last move, mistakes and all. Hint lights one provably safe cell whenever its cooldown is ready.",
	},
]

@onready var play_button: Button = $VBoxContainer/PlayButton
@onready var daily_button: Button = $VBoxContainer/DailyButton
@onready var tutorial_button: Button = $VBoxContainer/TutorialButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton
@onready var select_button: Button = $VBoxContainer/SelectButton
@onready var archive_button: Button = $VBoxContainer/ArchiveButton
@onready var title: Label = $Title
@onready var tagline: Label = $Tagline
@onready var profile_label: Label = $ProfileLabel
@onready var menu_container: VBoxContainer = $VBoxContainer
@onready var menu_card: Panel = get_node_or_null("MenuCard") as Panel
@onready var title_rule: Panel = get_node_or_null("TitleRule") as Panel
@onready var tutorial_hint: Label = get_node_or_null("TutorialHint") as Label
@onready var settings_panel: Panel = get_node_or_null("SettingsPanel") as Panel
@onready var settings_scrim: ColorRect = get_node_or_null("SettingsScrim") as ColorRect
@onready var how_to_play_modal: Control = get_node_or_null("HowToPlayModal") as Control
@onready var how_to_play_scrim: ColorRect = get_node_or_null("HowToPlayModal/HowToPlayScrim") as ColorRect
@onready var how_to_play_panel: PanelContainer = get_node_or_null("HowToPlayModal/Panel") as PanelContainer
@onready var how_to_play_steps: VBoxContainer = get_node_or_null("HowToPlayModal/Panel/Margin/VBoxContainer/Scroll/Steps") as VBoxContainer
@onready var how_to_play_back_button: Button = get_node_or_null("HowToPlayModal/Panel/Margin/VBoxContainer/ActionRow/BackButton") as Button
@onready var how_to_play_start_button: Button = get_node_or_null("HowToPlayModal/Panel/Margin/VBoxContainer/ActionRow/StartPracticeButton") as Button
@onready var difficulty_modal: Control = get_node_or_null("DifficultyModal") as Control
@onready var difficulty_scrim: ColorRect = get_node_or_null("DifficultyModal/DifficultyScrim") as ColorRect
@onready var difficulty_panel: Panel = get_node_or_null("DifficultyModal/Panel") as Panel
@onready var difficulty_description_label: Label = get_node_or_null("DifficultyModal/Panel/VBoxContainer/DifficultyDescriptionLabel") as Label

var _settings_open: bool = false
var _difficulty_open: bool = false
var _how_to_play_open: bool = false
var _settings_opener: Button = null
var _background_buttons: Array[Button] = []


func _ready() -> void:
	_background_buttons = [play_button, daily_button, tutorial_button, select_button, archive_button, settings_button]
	_apply_focus_style(_background_buttons)
	for button in _background_buttons:
		if is_instance_valid(button) and not button.focus_entered.is_connected(_on_menu_focus_entered):
			button.focus_entered.connect(_on_menu_focus_entered)

	play_button.pressed.connect(_on_play_pressed)
	daily_button.pressed.connect(_on_daily_pressed)
	tutorial_button.pressed.connect(_on_tutorial_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	if is_instance_valid(select_button):
		select_button.pressed.connect(_on_select_pressed)
	if is_instance_valid(archive_button):
		archive_button.pressed.connect(_on_archive_pressed)

	var easy_button: Button = get_node_or_null("DifficultyModal/Panel/VBoxContainer/EasyButton") as Button
	var medium_button: Button = get_node_or_null("DifficultyModal/Panel/VBoxContainer/MediumButton") as Button
	var hard_button: Button = get_node_or_null("DifficultyModal/Panel/VBoxContainer/HardButton") as Button
	var endless_button: Button = get_node_or_null("DifficultyModal/Panel/VBoxContainer/EndlessButton") as Button
	var cancel_button: Button = get_node_or_null("DifficultyModal/Panel/VBoxContainer/CloseDifficultyButton") as Button
	if easy_button:
		easy_button.pressed.connect(_on_difficulty_selected.bind("easy"))
		easy_button.focus_entered.connect(_preview_difficulty.bind("easy"))
	if medium_button:
		medium_button.pressed.connect(_on_difficulty_selected.bind("medium"))
		medium_button.focus_entered.connect(_preview_difficulty.bind("medium"))
	if hard_button:
		hard_button.pressed.connect(_on_difficulty_selected.bind("hard"))
		hard_button.focus_entered.connect(_preview_difficulty.bind("hard"))
	if endless_button:
		endless_button.pressed.connect(_on_difficulty_selected.bind("endless"))
		endless_button.focus_entered.connect(_preview_difficulty.bind("endless"))
	if cancel_button:
		cancel_button.pressed.connect(_hide_difficulty_modal)
	_apply_focus_style([easy_button, medium_button, hard_button, endless_button, cancel_button])

	if settings_scrim:
		settings_scrim.gui_input.connect(_on_blocking_scrim_input)
	if how_to_play_scrim:
		how_to_play_scrim.gui_input.connect(_on_blocking_scrim_input)
	if difficulty_scrim:
		difficulty_scrim.gui_input.connect(_on_blocking_scrim_input)
	if how_to_play_back_button:
		how_to_play_back_button.pressed.connect(_hide_how_to_play)
	if how_to_play_start_button:
		how_to_play_start_button.pressed.connect(_start_tutorial_practice)
	_apply_focus_style([how_to_play_back_button, how_to_play_start_button])
	_build_how_to_play_content()
	if settings_panel and settings_panel.has_signal("closed"):
		settings_panel.connect("closed", Callable(self, "_on_settings_closed"))
	if settings_panel:
		settings_panel.visibility_changed.connect(_on_settings_visibility_changed)

	resized.connect(_apply_responsive_layout)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")
	call_deferred("_safe_focus", play_button)
	_refresh_profile_summary()
	# Deferred so the GameManager's own deferred settings load has already told
	# us whether this profile has seen the tutorial.
	call_deferred("_refresh_tutorial_hint")

	if title:
		title.clip_text = false
		title.autowrap_mode = TextServer.AUTOWRAP_OFF


## Builds the written rules from HOW_TO_PLAY_STEPS so the copy lives in one
## reviewable place instead of being spread across scene node text.
func _build_how_to_play_content() -> void:
	if how_to_play_steps == null or not is_instance_valid(how_to_play_steps):
		return
	for child in how_to_play_steps.get_children():
		child.queue_free()
	how_to_play_steps.add_child(_make_how_to_play_card(
		"GOAL",
		HOW_TO_PLAY_GOAL_TITLE,
		HOW_TO_PLAY_GOAL_BODY,
		true,
	))
	for index in range(HOW_TO_PLAY_STEPS.size()):
		var step: Dictionary = HOW_TO_PLAY_STEPS[index]
		how_to_play_steps.add_child(_make_how_to_play_card(
			str(index + 1),
			str(step.get("heading", "")),
			str(step.get("body", "")),
			false,
		))


func _make_how_to_play_card(badge: String, heading: String, body: String, is_goal: bool) -> PanelContainer:
	var card := PanelContainer.new()
	if is_goal:
		card.add_theme_stylebox_override("panel", _make_card_stylebox(Color(0.298, 0.478, 0.902, 0.16), Color(0.588, 0.788, 1, 0.38), 16))
	else:
		card.add_theme_stylebox_override("panel", _make_card_stylebox(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.1), 16))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var badge_panel := PanelContainer.new()
	badge_panel.add_theme_stylebox_override("panel", _make_card_stylebox(Color(0.976, 0.627, 0.278, 1), Color(0, 0, 0, 0), 12))
	badge_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	badge_panel.custom_minimum_size = Vector2(58.0, 42.0)
	row.add_child(badge_panel)

	var badge_margin := MarginContainer.new()
	badge_margin.add_theme_constant_override("margin_left", 6)
	badge_margin.add_theme_constant_override("margin_right", 6)
	badge_panel.add_child(badge_margin)

	var badge_label := Label.new()
	badge_label.text = badge
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_label.add_theme_font_size_override("font_size", 16)
	badge_label.add_theme_color_override("font_color", Color(0.129, 0.063, 0.157, 1) if not is_goal else Color(0.976, 0.788, 0.502, 1))
	badge_margin.add_child(badge_label)

	var text_column := VBoxContainer.new()
	text_column.add_theme_constant_override("separation", 3)
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_column)

	var heading_label := Label.new()
	heading_label.text = heading
	heading_label.add_theme_font_size_override("font_size", 19)
	heading_label.add_theme_color_override("font_color", Color(1, 0.976, 0.949, 1))
	heading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_column.add_child(heading_label)

	var body_label := Label.new()
	body_label.text = body
	body_label.add_theme_font_size_override("font_size", 15)
	body_label.add_theme_color_override("font_color", Color(0.816, 0.839, 0.906, 1))
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_column.add_child(body_label)

	return card


## Builds a rounded glass card. Kept in code so the rule cards look identical
## no matter which screen embeds them.
func _make_card_stylebox(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	return style


func _set_how_to_play_open(open: bool) -> void:
	_how_to_play_open = open
	if how_to_play_modal:
		how_to_play_modal.visible = open
	if how_to_play_scrim:
		how_to_play_scrim.visible = open
	_set_background_blocked(open or _settings_open or _difficulty_open)
	if open:
		call_deferred("_focus_how_to_play")


func _focus_how_to_play() -> void:
	if how_to_play_start_button and is_instance_valid(how_to_play_start_button):
		how_to_play_start_button.grab_focus()


func _hide_how_to_play() -> void:
	_set_how_to_play_open(false)
	if tutorial_button and is_inside_tree() and tutorial_button.is_inside_tree():
		call_deferred("_safe_focus", tutorial_button)


func _on_blocking_scrim_input(event: InputEvent) -> void:
	# The scrim is intentionally a blocker, not a dismiss target. This keeps
	# touch and mouse input from reaching the menu behind a modal.
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _settings_open:
		_set_settings_open(false)
		get_viewport().set_input_as_handled()
	elif _difficulty_open:
		_hide_difficulty_modal()
		get_viewport().set_input_as_handled()
	elif _how_to_play_open:
		_hide_how_to_play()
		get_viewport().set_input_as_handled()


func _set_settings_open(open: bool) -> void:
	_settings_open = open
	if settings_scrim:
		settings_scrim.visible = open
	if settings_panel:
		if open:
			settings_panel.call("show_modal", self)
		else:
			settings_panel.call("hide_modal")
	_set_background_blocked(open or _difficulty_open or _how_to_play_open)
	if open:
		call_deferred("_focus_settings")


func _apply_focus_style(buttons: Array) -> void:
	var focus_style := StyleBoxFlat.new()
	# A focus indicator has to stay an indicator. It used to paint an opaque
	# navy fill, which completely covered the amber primary button whenever it
	# held focus, so the screen's focal point changed with keyboard navigation.
	focus_style.draw_center = false
	focus_style.bg_color = Color(0, 0, 0, 0)
	focus_style.border_width_left = 3
	focus_style.border_width_top = 3
	focus_style.border_width_right = 3
	focus_style.border_width_bottom = 3
	focus_style.border_color = Color(1.0, 0.902, 0.549, 0.95)
	focus_style.corner_radius_top_left = 8
	focus_style.corner_radius_top_right = 8
	focus_style.corner_radius_bottom_right = 8
	focus_style.corner_radius_bottom_left = 8
	for button in buttons:
		if is_instance_valid(button):
			button.add_theme_stylebox_override("focus", focus_style)


func _on_menu_focus_entered() -> void:
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_menu_move_sfx"):
		audio_manager.call("play_menu_move_sfx")


func _safe_focus(control: Control) -> void:
	if is_inside_tree() and is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree():
		control.grab_focus()


func _focus_settings() -> void:
	if _settings_open and settings_panel and settings_panel.has_method("focus_first_control"):
		settings_panel.call("focus_first_control")
	elif is_instance_valid(_settings_opener):
		call_deferred("_safe_focus", _settings_opener)


func _on_settings_closed() -> void:
	if _settings_open:
		_set_settings_open(false)


func _on_settings_visibility_changed() -> void:
	if settings_panel == null:
		return
	if settings_panel.visible and not _settings_open:
		_set_settings_open(true)
	elif not settings_panel.visible and _settings_open:
		_set_settings_open(false)


func _set_difficulty_open(open: bool) -> void:
	_difficulty_open = open
	if difficulty_modal:
		difficulty_modal.visible = open
	if difficulty_scrim:
		difficulty_scrim.visible = open
	if title:
		title.visible = not open
	if menu_container:
		menu_container.visible = not open
	_sync_menu_card()
	_set_background_blocked(open or _settings_open or _how_to_play_open)
	if open:
		_preview_difficulty("easy")
		var first_button: Button = get_node_or_null("DifficultyModal/Panel/VBoxContainer/EasyButton") as Button
		if first_button:
			call_deferred("_safe_focus", first_button)


func _set_background_blocked(blocked: bool) -> void:
	for button in _background_buttons:
		if is_instance_valid(button):
			button.disabled = blocked
	if menu_container:
		menu_container.mouse_filter = Control.MOUSE_FILTER_IGNORE if blocked else Control.MOUSE_FILTER_PASS
	if title:
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background: Control = get_node_or_null("Background") as Control
	if background:
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE if blocked else Control.MOUSE_FILTER_STOP


func _preview_difficulty(mode: String) -> void:
	if not difficulty_description_label:
		return
	var descriptions: Dictionary = {
		"easy": "Learn the loop  •  smaller deduction grids",
		"medium": "Balanced deduction  •  the intended first run",
		"hard": "Denser grids  •  plan slices before carving",
		"endless": "Seeded progression  •  chase a deeper personal best",
	}
	difficulty_description_label.text = str(descriptions.get(mode, descriptions["medium"]))


func _hide_difficulty_modal() -> void:
	_set_difficulty_open(false)
	if play_button and is_inside_tree() and play_button.is_inside_tree():
		call_deferred("_safe_focus", play_button)


func _on_play_pressed() -> void:
	# The background column is blocked while the rules are open, but closing any
	# other modal here keeps the surfaces mutually exclusive even if a future
	# entry point forgets to unblock first.
	_set_how_to_play_open(false)
	if difficulty_modal:
		_set_difficulty_open(true)
	else:
		_switch_mode(GameManagerClass.GameMode.ESCAPE_GAUNTLET)


func _on_tutorial_pressed() -> void:
	# The button used to drop straight into the puzzle, so a player asking how
	# the game works got a timer and a grid instead of an answer. Show the
	# written rules first; the guided practice is one explicit action away.
	_set_how_to_play_open(true)


func _start_tutorial_practice() -> void:
	if not FileAccess.file_exists(TUTORIAL_PUZZLE_PATH):
		push_warning("[MainMenu] Tutorial puzzle is unavailable")
		_set_how_to_play_open(false)
		return
	var file: FileAccess = FileAccess.open(TUTORIAL_PUZZLE_PATH, FileAccess.READ)
	if file == null:
		_set_how_to_play_open(false)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_warning("[MainMenu] Tutorial puzzle could not be parsed")
		_set_how_to_play_open(false)
		return
	var game_manager: Node = _get_game_manager()
	if game_manager and game_manager.has_method("switch_mode"):
		_set_how_to_play_open(false)
		game_manager.call("switch_mode", GameManagerClass.GameMode.VOXEL_LOGIC, {
			"custom_puzzle": parsed,
			"tutorial": true,
		})


func _on_daily_pressed() -> void:
	var game_manager: Node = _get_game_manager()
	if game_manager and game_manager.has_method("begin_daily_challenge"):
		var result: Variant = game_manager.call("begin_daily_challenge")
		if result is Dictionary and not bool((result as Dictionary).get("success", false)):
			push_warning("[MainMenu] Daily Challenge could not be created")


func _on_select_pressed() -> void:
	_switch_mode(GameManagerClass.GameMode.PUZZLE_SELECTION)


func _on_archive_pressed() -> void:
	_switch_mode(GameManagerClass.GameMode.ARCHIVE)


func _on_settings_pressed() -> void:
	_set_how_to_play_open(false)
	_settings_opener = settings_button
	_set_settings_open(true)


func _on_difficulty_selected(mode: String) -> void:
	var normalized_mode: String = mode.strip_edges().to_lower()
	if not (normalized_mode in ["easy", "medium", "hard", "endless"]):
		push_warning("[MainMenu] Ignoring unsupported difficulty: %s" % mode)
		return
	var game_manager: Node = _get_game_manager()
	if game_manager == null:
		push_warning("[MainMenu] GameManager is unavailable")
		return
	if game_manager.has_method("begin_run"):
		game_manager.call("begin_run", normalized_mode)
	else:
		game_manager.set("selected_difficulty_mode", normalized_mode)
		_switch_mode(GameManagerClass.GameMode.ESCAPE_GAUNTLET, {
			"difficulty": normalized_mode,
			"run_seed": 0,
		})
	_hide_difficulty_modal()


func _switch_mode(mode: int, payload: Dictionary = {}) -> void:
	var game_manager: Node = _get_game_manager()
	if game_manager and game_manager.has_method("switch_mode"):
		game_manager.call("switch_mode", mode, payload)


func _refresh_profile_summary() -> void:
	if not profile_label:
		return
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("get_player_stats"):
		profile_label.text = "New profile  •  Best depth: 0"
		return
	var stats: Dictionary = save_manager.call("get_player_stats")
	var best_depth: int = maxi(0, int(stats.get("gauntlet_max_depth", 0)))
	var best_streak: int = maxi(0, int(stats.get("best_streak", 0)))
	if best_depth > 0:
		profile_label.text = "Best depth: %d  •  Best streak: %d" % [best_depth, best_streak]
	else:
		profile_label.text = "New profile  •  Your first reveal starts here"


func _refresh_tutorial_hint() -> void:
	if tutorial_hint == null:
		return
	var game_manager: Node = _get_game_manager()
	var completed: bool = game_manager != null and bool(game_manager.get("tutorial_completed"))
	tutorial_hint.visible = not completed


func _get_game_manager() -> Node:
	var scene_tree: SceneTree = get_tree()
	if scene_tree == null or scene_tree.root == null:
		return null
	return scene_tree.root.get_node_or_null("GameManager")


func _apply_responsive_layout() -> void:
	if not is_inside_tree():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var insets: Vector4 = _get_safe_area_insets(viewport_size)
	var available_width: float = maxf(1.0, viewport_size.x - insets.x - insets.z)
	var available_height: float = maxf(1.0, viewport_size.y - insets.y - insets.w)
	var display_size: Vector2 = _get_display_size()
	var ui_scale: float = _get_ui_scale(viewport_size, display_size)
	var compact: bool = display_size.x < 600.0 or display_size.y < 520.0
	var very_short: bool = display_size.y < 420.0
	var menu_width: float = minf(360.0 * ui_scale, maxf(1.0, available_width - 24.0 * ui_scale))
	var menu_height: float = minf(440.0 * ui_scale, maxf(1.0, available_height - 116.0 * ui_scale))
	var separation: int = int((4 if very_short else 8 if compact else 14) * ui_scale)
	var button_height: int = int((44 if very_short else 48 if compact else 56) * ui_scale)

	if menu_container:
		menu_container.anchor_left = 0.5
		menu_container.anchor_right = 0.5
		menu_container.anchor_top = 0.5
		menu_container.anchor_bottom = 0.5
		menu_container.offset_left = -menu_width * 0.5
		menu_container.offset_right = menu_width * 0.5
		menu_container.offset_top = -menu_height * 0.5 + 44.0 * ui_scale
		menu_container.offset_bottom = menu_height * 0.5 + 24.0 * ui_scale
		menu_container.add_theme_constant_override("separation", separation)
		for child in menu_container.get_children():
			if child is Button:
				var button: Button = child as Button
				button.custom_minimum_size = Vector2(0.0, float(button_height))
				button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				button.clip_text = true
				button.focus_mode = Control.FOCUS_ALL
	_sync_menu_card()

	if title:
		var title_width: float = minf(maxf(available_width - 24.0 * ui_scale, 260.0 * ui_scale), 560.0 * ui_scale)
		title.anchor_left = 0.5
		title.anchor_right = 0.5
		title.anchor_top = 0.0
		title.anchor_bottom = 0.0
		title.offset_left = -title_width * 0.5
		title.offset_right = title_width * 0.5
		title.offset_top = insets.y + (8.0 if compact else 24.0) * ui_scale
		title.offset_bottom = title.offset_top + (48.0 if compact else 64.0) * ui_scale
		title.add_theme_font_size_override("font_size", int((36 if display_size.x < 600 else 48) * ui_scale))
		title.clip_text = false
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.pivot_offset = title.size * 0.5
	if title_rule:
		# Sits on the gap between the title and the tagline so the wordmark has
		# a visible baseline instead of floating on the backdrop.
		title_rule.anchor_left = 0.5
		title_rule.anchor_right = 0.5
		title_rule.anchor_top = 0.0
		title_rule.anchor_bottom = 0.0
		var rule_width: float = minf(220.0 * ui_scale, 280.0 * ui_scale)
		var rule_height: float = maxf(2.0, 4.0 * ui_scale)
		title_rule.offset_left = -rule_width * 0.5
		title_rule.offset_right = rule_width * 0.5
		title_rule.offset_top = title.offset_bottom + 2.0 * ui_scale
		title_rule.offset_bottom = title_rule.offset_top + rule_height
	if tagline:
		tagline.visible = not compact
		tagline.anchor_left = 0.0
		tagline.anchor_right = 1.0
		tagline.offset_left = 12.0 * ui_scale
		tagline.offset_right = -12.0 * ui_scale
		tagline.offset_top = title.offset_bottom + (4.0 if compact else 8.0) * ui_scale
		tagline.offset_bottom = tagline.offset_top + (28.0 if compact else 32.0) * ui_scale
		tagline.add_theme_font_size_override("font_size", int((14 if compact else 18) * ui_scale))
	if profile_label:
		profile_label.visible = not very_short
		profile_label.anchor_left = 0.0
		profile_label.anchor_right = 1.0
		profile_label.offset_left = 12.0 * ui_scale
		profile_label.offset_right = -12.0 * ui_scale
		profile_label.offset_top = (tagline.offset_bottom + 2.0) if tagline and tagline.visible else (title.offset_bottom + 4.0)
		profile_label.offset_bottom = profile_label.offset_top + 24.0 * ui_scale
		profile_label.add_theme_font_size_override("font_size", int((12 if compact else 15) * ui_scale))
	if tutorial_hint:
		tutorial_hint.anchor_left = 0.0
		tutorial_hint.anchor_right = 1.0
		tutorial_hint.offset_left = 12.0 * ui_scale
		tutorial_hint.offset_right = -12.0 * ui_scale
		if profile_label and profile_label.visible:
			tutorial_hint.offset_top = profile_label.offset_bottom + 2.0 * ui_scale
		else:
			tutorial_hint.offset_top = (tagline.offset_bottom + 2.0) if tagline and tagline.visible else (title.offset_bottom + 6.0 * ui_scale)
		tutorial_hint.offset_bottom = tutorial_hint.offset_top + 22.0 * ui_scale
		tutorial_hint.add_theme_font_size_override("font_size", int((12 if compact else 14) * ui_scale))

	if how_to_play_panel:
		_layout_how_to_play_modal(available_width, available_height, ui_scale, compact)

	if settings_panel:
		var settings_width: float = minf(420.0 * ui_scale, maxf(1.0, available_width - 24.0 * ui_scale))
		var settings_height: float = minf(470.0 * ui_scale, maxf(1.0, available_height - 24.0 * ui_scale))
		settings_panel.anchor_left = 0.5
		settings_panel.anchor_right = 0.5
		settings_panel.anchor_top = 0.5
		settings_panel.anchor_bottom = 0.5
		settings_panel.offset_left = -settings_width * 0.5
		settings_panel.offset_right = settings_width * 0.5
		settings_panel.offset_top = -settings_height * 0.5
		settings_panel.offset_bottom = settings_height * 0.5
		var settings_content: VBoxContainer = settings_panel.get_node_or_null("VBoxContainer") as VBoxContainer
		if settings_content:
			settings_content.offset_left = (20.0 if compact else 40.0) * ui_scale
			settings_content.offset_right = (-20.0 if compact else -40.0) * ui_scale
			settings_content.offset_top = (64.0 if compact else 80.0) * ui_scale
			settings_content.offset_bottom = (-64.0 if compact else -80.0) * ui_scale
			settings_content.add_theme_constant_override("separation", int((12 if compact else 20) * ui_scale))
		var settings_title: Label = settings_panel.get_node_or_null("Title") as Label
		if settings_title:
			settings_title.offset_top = (14.0 if compact else 20.0) * ui_scale
			settings_title.offset_bottom = settings_title.offset_top + (34.0 if compact else 40.0) * ui_scale
			settings_title.add_theme_font_size_override("font_size", int((26 if compact else 32) * ui_scale))
		var close_button: Button = settings_panel.get_node_or_null("CloseButton") as Button
		if close_button:
			close_button.custom_minimum_size = Vector2(120.0 * ui_scale, (44.0 if compact else 50.0) * ui_scale)
			close_button.offset_top = (-54.0 if compact else -60.0) * ui_scale
			close_button.offset_bottom = (-14.0 if compact else -20.0) * ui_scale

	if difficulty_panel:
		var difficulty_width: float = minf(360.0 * ui_scale, maxf(1.0, available_width - 24.0 * ui_scale))
		var difficulty_height: float = minf(480.0 * ui_scale, maxf(1.0, available_height - 24.0 * ui_scale))
		difficulty_panel.anchor_left = 0.5
		difficulty_panel.anchor_right = 0.5
		difficulty_panel.anchor_top = 0.5
		difficulty_panel.anchor_bottom = 0.5
		difficulty_panel.offset_left = -difficulty_width * 0.5
		difficulty_panel.offset_right = difficulty_width * 0.5
		difficulty_panel.offset_top = -difficulty_height * 0.5
		difficulty_panel.offset_bottom = difficulty_height * 0.5
		var difficulty_content: VBoxContainer = difficulty_panel.get_node_or_null("VBoxContainer") as VBoxContainer
		if difficulty_content:
			difficulty_content.offset_left = (18.0 if compact else 24.0) * ui_scale
			difficulty_content.offset_right = (-18.0 if compact else -24.0) * ui_scale
			difficulty_content.offset_top = (18.0 if compact else 24.0) * ui_scale
			difficulty_content.offset_bottom = (-18.0 if compact else -24.0) * ui_scale
			difficulty_content.add_theme_constant_override("separation", int((10 if compact else 16) * ui_scale))
		var difficulty_title: Label = difficulty_panel.get_node_or_null("VBoxContainer/Label") as Label
		if difficulty_title:
			difficulty_title.add_theme_font_size_override("font_size", int((26 if compact else 32) * ui_scale))
		if difficulty_description_label:
			difficulty_description_label.add_theme_font_size_override("font_size", int((12 if compact else 15) * ui_scale))
		var difficulty_children: Node = difficulty_panel.get_node_or_null("VBoxContainer")
		if difficulty_children:
			for difficulty_button in difficulty_children.get_children():
				if difficulty_button is Button:
					var button: Button = difficulty_button as Button
					button.custom_minimum_size = Vector2(0.0, (48.0 if compact else 52.0) * ui_scale)
					button.clip_text = true
					button.focus_mode = Control.FOCUS_ALL


## Keeps the glass card behind the button column glued to the buttons, so the
## column reads as one surface instead of six floating chips.
func _sync_menu_card() -> void:
	if menu_card == null or menu_container == null:
		return
	var buttons_visible: bool = menu_container.is_visible_in_tree()
	menu_card.visible = buttons_visible
	if not buttons_visible:
		return
	var padding_x: float = 20.0
	var padding_y: float = 18.0
	var menu_rect: Rect2 = menu_container.get_global_rect()
	# The column is anchored to a nominal height, so hug the buttons' real
	# content instead of the anchor rect; otherwise the card grows a dead band
	# under the last button.
	var content_height: float = menu_container.get_combined_minimum_size().y
	var content_top: float = menu_rect.position.y + (menu_rect.size.y - content_height) * 0.5
	menu_card.position = Vector2(menu_rect.position.x - padding_x, content_top - padding_y)
	menu_card.size = Vector2(menu_rect.size.x + padding_x * 2.0, content_height + padding_y * 2.0)


func _layout_how_to_play_modal(available_width: float, available_height: float, ui_scale: float, compact: bool) -> void:
	var panel_width: float = minf(840.0 * ui_scale, maxf(1.0, available_width - 24.0 * ui_scale))
	# Tall enough that all seven cards fit on the 1080px reference canvas, and
	# still scrollable on a short landscape phone rather than clipping a rule.
	var panel_height: float = minf(700.0 * ui_scale, maxf(1.0, available_height - 24.0 * ui_scale))
	how_to_play_panel.anchor_left = 0.5
	how_to_play_panel.anchor_right = 0.5
	how_to_play_panel.anchor_top = 0.5
	how_to_play_panel.anchor_bottom = 0.5
	how_to_play_panel.offset_left = -panel_width * 0.5
	how_to_play_panel.offset_right = panel_width * 0.5
	how_to_play_panel.offset_top = -panel_height * 0.5
	how_to_play_panel.offset_bottom = panel_height * 0.5

	var margin: MarginContainer = how_to_play_panel.get_node_or_null("Margin") as MarginContainer
	var side: float = (16.0 if compact else 26.0) * ui_scale
	if margin:
		margin.add_theme_constant_override("margin_left", int(side))
		margin.add_theme_constant_override("margin_right", int(side))
		margin.add_theme_constant_override("margin_top", int((14.0 if compact else 22.0) * ui_scale))
		margin.add_theme_constant_override("margin_bottom", int((12.0 if compact else 20.0) * ui_scale))
	var content: VBoxContainer = how_to_play_panel.get_node_or_null("Margin/VBoxContainer") as VBoxContainer
	if content:
		content.add_theme_constant_override("separation", int((6 if compact else 10) * ui_scale))
	var panel_title: Label = how_to_play_panel.get_node_or_null("Margin/VBoxContainer/Title") as Label
	if panel_title:
		panel_title.add_theme_font_size_override("font_size", int((24 if compact else 32) * ui_scale))
	var subtitle: Label = how_to_play_panel.get_node_or_null("Margin/VBoxContainer/Subtitle") as Label
	if subtitle:
		subtitle.add_theme_font_size_override("font_size", int((12 if compact else 15) * ui_scale))
	var footnote: Label = how_to_play_panel.get_node_or_null("Margin/VBoxContainer/Footnote") as Label
	if footnote:
		footnote.add_theme_font_size_override("font_size", int((11 if compact else 13) * ui_scale))
	var action_row: Control = how_to_play_panel.get_node_or_null("Margin/VBoxContainer/ActionRow") as Control
	if action_row:
		action_row.custom_minimum_size = Vector2(0.0, (48.0 if compact else 52.0) * ui_scale)
		for action_button in [how_to_play_back_button, how_to_play_start_button]:
			if is_instance_valid(action_button):
				(action_button as Button).custom_minimum_size = Vector2(
					(120.0 if compact else 150.0) * ui_scale,
					(48.0 if compact else 52.0) * ui_scale
				)
				(action_button as Button).clip_text = true
				(action_button as Button).focus_mode = Control.FOCUS_ALL


func _get_display_size() -> Vector2:
	var window_size := Vector2(DisplayServer.window_get_size())
	return window_size if window_size.x > 0.0 and window_size.y > 0.0 else get_viewport_rect().size


func _get_ui_scale(viewport_size: Vector2, display_size: Vector2) -> float:
	if display_size.x <= 0.0 or display_size.y <= 0.0:
		return 1.0
	return clampf(maxf(viewport_size.x / display_size.x, viewport_size.y / display_size.y), 1.0, 4.0)


func _get_safe_area_insets(viewport_size: Vector2) -> Vector4:
	var minimum_insets: Vector4 = Vector4(12.0, 12.0, 12.0, 12.0)
	if DisplayServer.get_name() == "headless":
		return minimum_insets
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	if safe_area.size.x <= 0 or safe_area.size.y <= 0:
		return minimum_insets
	var window_size: Vector2 = Vector2(DisplayServer.window_get_size())
	var scale: Vector2 = Vector2.ONE
	if window_size.x > 0.0 and window_size.y > 0.0:
		scale = viewport_size / window_size
	var safe_min: Vector2 = Vector2(safe_area.position) * scale
	var safe_max: Vector2 = Vector2(safe_area.position + safe_area.size) * scale
	return Vector4(
		maxf(minimum_insets.x, safe_min.x),
		maxf(minimum_insets.y, safe_min.y),
		maxf(minimum_insets.z, viewport_size.x - safe_max.x),
		maxf(minimum_insets.w, viewport_size.y - safe_max.y)
	)
