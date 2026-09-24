extends Control

const GameManagerClass = preload("res://scripts/GameManager.gd")

@onready var play_button: Button = $VBoxContainer/PlayButton
@onready var editor_button: Button = $VBoxContainer/EditorButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton
@onready var select_button: Button = $VBoxContainer/SelectButton
@onready var title: Label = $Title
@onready var menu_container: VBoxContainer = $VBoxContainer
@onready var settings_panel: Panel = get_node_or_null("SettingsPanel") as Panel
@onready var settings_scrim: ColorRect = get_node_or_null("SettingsScrim") as ColorRect
@onready var difficulty_modal: Control = get_node_or_null("DifficultyModal") as Control
@onready var difficulty_scrim: ColorRect = get_node_or_null("DifficultyModal/DifficultyScrim") as ColorRect
@onready var difficulty_panel: Panel = get_node_or_null("DifficultyModal/Panel") as Panel

var _settings_open: bool = false
var _difficulty_open: bool = false
var _settings_opener: Button = null
var _background_buttons: Array[Button] = []


func _ready() -> void:
	_background_buttons = [play_button, select_button, settings_button]
	if is_instance_valid(editor_button):
		_background_buttons.append(editor_button)

	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	if is_instance_valid(select_button):
		select_button.pressed.connect(_on_select_pressed)
	if is_instance_valid(editor_button):
		editor_button.pressed.connect(_on_editor_pressed)
		# The editor is not part of the shipping menu, but retain the old
		# node long enough for callers that inspect the scene during startup.
		editor_button.queue_free()

	var easy_button: Button = get_node_or_null("DifficultyModal/Panel/VBoxContainer/EasyButton") as Button
	var medium_button: Button = get_node_or_null("DifficultyModal/Panel/VBoxContainer/MediumButton") as Button
	var hard_button: Button = get_node_or_null("DifficultyModal/Panel/VBoxContainer/HardButton") as Button
	var endless_button: Button = get_node_or_null("DifficultyModal/Panel/VBoxContainer/EndlessButton") as Button
	var cancel_button: Button = get_node_or_null("DifficultyModal/Panel/VBoxContainer/CloseDifficultyButton") as Button
	if easy_button:
		easy_button.pressed.connect(_on_difficulty_selected.bind("easy"))
	if medium_button:
		medium_button.pressed.connect(_on_difficulty_selected.bind("medium"))
	if hard_button:
		hard_button.pressed.connect(_on_difficulty_selected.bind("hard"))
	if endless_button:
		endless_button.pressed.connect(_on_difficulty_selected.bind("endless"))
	if cancel_button:
		cancel_button.pressed.connect(_hide_difficulty_modal)

	if settings_scrim:
		settings_scrim.gui_input.connect(_on_blocking_scrim_input)
	if difficulty_scrim:
		difficulty_scrim.gui_input.connect(_on_blocking_scrim_input)
	if settings_panel and settings_panel.has_signal("closed"):
		settings_panel.connect("closed", Callable(self, "_on_settings_closed"))
	if settings_panel:
		settings_panel.visibility_changed.connect(_on_settings_visibility_changed)

	resized.connect(_apply_responsive_layout)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")

	if title:
		var title_tween: Tween = create_tween().set_loops()
		title_tween.tween_property(title, "scale", Vector2(1.05, 1.05), 1.0).set_trans(Tween.TRANS_SINE)
		title_tween.tween_property(title, "scale", Vector2(1.0, 1.0), 1.0).set_trans(Tween.TRANS_SINE)


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


func _set_settings_open(open: bool) -> void:
	_settings_open = open
	if settings_scrim:
		settings_scrim.visible = open
	if settings_panel:
		if open:
			settings_panel.call("show_modal", self)
		else:
			settings_panel.call("hide_modal")
	_set_background_blocked(open or _difficulty_open)
	if open:
		call_deferred("_focus_settings")


func _focus_settings() -> void:
	if _settings_open and settings_panel and settings_panel.has_method("focus_first_control"):
		settings_panel.call("focus_first_control")
	elif is_instance_valid(_settings_opener):
		_settings_opener.call_deferred("grab_focus")


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
	_set_background_blocked(open or _settings_open)
	if open:
		var first_button: Button = get_node_or_null("DifficultyModal/Panel/VBoxContainer/EasyButton") as Button
		if first_button:
			first_button.call_deferred("grab_focus")


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


func _hide_difficulty_modal() -> void:
	_set_difficulty_open(false)
	if play_button:
		play_button.call_deferred("grab_focus")


func _on_play_pressed() -> void:
	if difficulty_modal:
		_set_difficulty_open(true)
	else:
		_switch_mode(GameManagerClass.GameMode.ESCAPE_GAUNTLET)


func _on_select_pressed() -> void:
	_switch_mode(GameManagerClass.GameMode.PUZZLE_SELECTION)


func _on_editor_pressed() -> void:
	_switch_mode(GameManagerClass.GameMode.PUZZLE_EDITOR)


func _on_settings_pressed() -> void:
	_settings_opener = settings_button
	_set_settings_open(true)


func _on_difficulty_selected(mode: String) -> void:
	var game_manager: Node = _get_game_manager()
	if game_manager:
		game_manager.set("selected_difficulty_mode", mode)
	_hide_difficulty_modal()
	_switch_mode(GameManagerClass.GameMode.ESCAPE_GAUNTLET)


func _switch_mode(mode: int) -> void:
	var game_manager: Node = _get_game_manager()
	if game_manager and game_manager.has_method("switch_mode"):
		game_manager.call("switch_mode", mode)


func _get_game_manager() -> Node:
	var scene_tree: SceneTree = get_tree()
	if scene_tree == null or scene_tree.root == null:
		return null
	return scene_tree.root.get_node_or_null("GameManager")


func _apply_responsive_layout() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var insets: Vector4 = _get_safe_area_insets(viewport_size)
	var available_width: float = maxf(1.0, viewport_size.x - insets.x - insets.z)
	var available_height: float = maxf(1.0, viewport_size.y - insets.y - insets.w)
	var menu_width: float = minf(360.0, maxf(1.0, available_width - 24.0))
	var menu_height: float = minf(292.0, maxf(1.0, available_height - 116.0))
	var compact: bool = viewport_size.x < 420.0 or viewport_size.y < 520.0
	var very_short: bool = viewport_size.y < 420.0
	var separation: int = 4 if very_short else 8 if compact else 14
	var button_height: int = 44 if very_short else 48 if compact else 56

	if menu_container:
		menu_container.anchor_left = 0.5
		menu_container.anchor_right = 0.5
		menu_container.anchor_top = 0.5
		menu_container.anchor_bottom = 0.5
		menu_container.offset_left = -menu_width * 0.5
		menu_container.offset_right = menu_width * 0.5
		menu_container.offset_top = -menu_height * 0.5 + 24.0
		menu_container.offset_bottom = menu_height * 0.5 + 24.0
		menu_container.add_theme_constant_override("separation", separation)
		for child in menu_container.get_children():
			if child is Button:
				var button: Button = child as Button
				button.custom_minimum_size = Vector2(0.0, float(button_height))
				button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				button.clip_text = true
				button.focus_mode = Control.FOCUS_ALL

	if title:
		title.anchor_left = 0.5
		title.anchor_right = 0.5
		title.anchor_top = 0.0
		title.anchor_bottom = 0.0
		title.offset_left = -menu_width * 0.5
		title.offset_right = menu_width * 0.5
		title.offset_top = insets.y + (8.0 if compact else 24.0)
		title.offset_bottom = title.offset_top + (48.0 if compact else 64.0)
		title.add_theme_font_size_override("font_size", 40 if compact else 56)
		title.clip_text = true
		title.pivot_offset = title.size * 0.5

	if settings_panel:
		var settings_width: float = minf(420.0, maxf(1.0, available_width - 24.0))
		var settings_height: float = minf(360.0, maxf(1.0, available_height - 24.0))
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
			settings_content.offset_left = 20.0 if compact else 40.0
			settings_content.offset_right = -20.0 if compact else -40.0
			settings_content.offset_top = 64.0 if compact else 80.0
			settings_content.offset_bottom = -64.0 if compact else -80.0
			settings_content.add_theme_constant_override("separation", 12 if compact else 20)
		var settings_title: Label = settings_panel.get_node_or_null("Title") as Label
		if settings_title:
			settings_title.offset_top = 14.0 if compact else 20.0
			settings_title.offset_bottom = settings_title.offset_top + (34.0 if compact else 40.0)
			settings_title.add_theme_font_size_override("font_size", 26 if compact else 32)
		var close_button: Button = settings_panel.get_node_or_null("CloseButton") as Button
		if close_button:
			close_button.custom_minimum_size = Vector2(120.0, 44.0 if compact else 50.0)
			close_button.offset_top = -54.0 if compact else -60.0
			close_button.offset_bottom = -14.0 if compact else -20.0

	if difficulty_panel:
		var difficulty_width: float = minf(360.0, maxf(1.0, available_width - 24.0))
		var difficulty_height: float = minf(480.0, maxf(1.0, available_height - 24.0))
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
			difficulty_content.offset_left = 18.0 if compact else 24.0
			difficulty_content.offset_right = -18.0 if compact else -24.0
			difficulty_content.offset_top = 18.0 if compact else 24.0
			difficulty_content.offset_bottom = -18.0 if compact else -24.0
			difficulty_content.add_theme_constant_override("separation", 10 if compact else 16)
		var difficulty_title: Label = difficulty_panel.get_node_or_null("VBoxContainer/Label") as Label
		if difficulty_title:
			difficulty_title.add_theme_font_size_override("font_size", 26 if compact else 32)
		var difficulty_children: Node = difficulty_panel.get_node_or_null("VBoxContainer")
		if difficulty_children:
			for difficulty_button in difficulty_children.get_children():
				if difficulty_button is Button:
					var button: Button = difficulty_button as Button
					button.custom_minimum_size = Vector2(0.0, 48.0 if compact else 52.0)
					button.clip_text = true
					button.focus_mode = Control.FOCUS_ALL


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
