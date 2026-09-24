extends Control

const GameManagerClass = preload("res://scripts/GameManager.gd")
const PuzzleRegistryClass = preload("res://scripts/PuzzleRegistry.gd")
const PuzzleDataValidatorClass = preload("res://scripts/PuzzleDataValidator.gd")
const DEFAULT_PANORAMA: Texture2D = preload("res://assets/textures/generated/abstract_panorama.svg")

@onready var category_panel: VBoxContainer = $HBoxContainer/CategoryPanel
@onready var category_list: VBoxContainer = $HBoxContainer/CategoryPanel/CategoryList
@onready var puzzle_panel: VBoxContainer = $HBoxContainer/PuzzlePanel
@onready var puzzle_scroll: ScrollContainer = $HBoxContainer/PuzzlePanel/ScrollContainer
@onready var puzzle_grid: GridContainer = $HBoxContainer/PuzzlePanel/ScrollContainer/PuzzleGrid
@onready var back_button: Button = $BackButton
@onready var title: Label = $Title
@onready var content: HBoxContainer = $HBoxContainer

# Predefined collections matching the bundled puzzle themes.
var collections: Dictionary = {
	"Tutorials": ["res://data/puzzles/tutorial_star.json", "res://assets/puzzles/tutorial/simple_hints.json"],
	"Animals": ["res://assets/puzzles/animals/horse.json", "res://assets/puzzles/animals/platypus.json", "res://assets/puzzles/animals/suzanne.json"],
	"Furniture": ["res://assets/puzzles/furniture/chair.json", "res://assets/puzzles/furniture/computer.json"],
	"Egypt": ["res://assets/puzzles/egypt/pyramid.json", "res://assets/puzzles/egypt/sphinx.json"],
	"Nature": ["res://assets/puzzles/nature/strange_tree.json"],
	"Valentine": ["res://assets/puzzles/valentine/heart.json", "res://assets/puzzles/valentine/love_letter.json", "res://assets/puzzles/valentine/diamond_ring.json", "res://assets/puzzles/valentine/rose.json", "res://assets/puzzles/valentine/bow_and_arrow.json"],
	"Fantasy": ["res://assets/puzzles/fantasy/vampire_fangs.json", "res://assets/puzzles/fantasy/werewolf_head.json", "res://assets/puzzles/fantasy/witch_hat.json", "res://assets/puzzles/fantasy/witch_house.json", "res://assets/puzzles/fantasy/wyvern.json", "res://assets/puzzles/fantasy/cthulhu.json"]
}

var btn_normal: StyleBoxFlat
var btn_hover: StyleBoxFlat


func _ready() -> void:
	btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.95, 0.45, 0.55, 1.0)
	btn_normal.corner_radius_top_left = 8
	btn_normal.corner_radius_top_right = 8
	btn_normal.corner_radius_bottom_right = 8
	btn_normal.corner_radius_bottom_left = 8
	btn_normal.shadow_color = Color(0.8, 0.2, 0.3, 0.3)
	btn_normal.shadow_size = 3
	btn_normal.shadow_offset = Vector2(0.0, 3.0)

	btn_hover = StyleBoxFlat.new()
	btn_hover.bg_color = Color(1.0, 0.55, 0.65, 1.0)
	btn_hover.corner_radius_top_left = 8
	btn_hover.corner_radius_top_right = 8
	btn_hover.corner_radius_bottom_right = 8
	btn_hover.corner_radius_bottom_left = 8
	btn_hover.shadow_color = Color(0.8, 0.2, 0.3, 0.2)
	btn_hover.shadow_size = 1
	btn_hover.shadow_offset = Vector2(0.0, 1.0)

	back_button.pressed.connect(_on_back_pressed)
	resized.connect(_apply_responsive_layout)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")

	var background: TextureRect = get_node_or_null("Background") as TextureRect
	if background:
		background.texture = DEFAULT_PANORAMA

	_build_category_menu()
	_load_category("Tutorials")


func _build_category_menu() -> void:
	var category_names: Array = collections.keys()
	category_names.sort()
	for category_value in category_names:
		var category_name: String = str(category_value)
		var button: Button = Button.new()
		button.text = category_name
		button.custom_minimum_size = Vector2(0.0, 48.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.tooltip_text = category_name
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_stylebox_override("normal", btn_normal)
		button.add_theme_stylebox_override("hover", btn_hover)
		button.add_theme_stylebox_override("pressed", btn_hover)
		button.pressed.connect(_load_category.bind(category_name))
		category_list.add_child(button)


func _load_category(category_name: String) -> void:
	for child in puzzle_grid.get_children():
		child.queue_free()

	var puzzles_to_show: Array[Dictionary] = []
	var file_paths: Array = collections.get(category_name, [])
	for path_value in file_paths:
		var path: String = str(path_value)
		if not FileAccess.file_exists(path):
			continue
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var json_text: String = file.get_as_text()
		file.close()
		var parsed_value: Variant = JSON.parse_string(json_text)
		if parsed_value is Dictionary:
			var analysis: Dictionary = PuzzleDataValidatorClass.analyze_puzzle(parsed_value as Dictionary, true, true)
			if bool(analysis.get("ok", false)):
				puzzles_to_show.append(analysis.get("puzzle", {}) as Dictionary)

	# If no explicit files matched, use the registered theme manifest.
	if puzzles_to_show.is_empty():
		var registry: PuzzleRegistryClass = PuzzleRegistryClass.new()
		registry.load_manifest()
		var theme_puzzles: Array = registry.load_theme(category_name.to_lower())
		var puzzle_limit: int = mini(18, theme_puzzles.size())
		for puzzle_index in range(puzzle_limit):
			var puzzle_value: Variant = theme_puzzles[puzzle_index]
			if puzzle_value is Dictionary:
				puzzles_to_show.append(puzzle_value as Dictionary)
		registry.free()

	if puzzles_to_show.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No validated puzzles are available in this category."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.custom_minimum_size = Vector2(0.0, 64.0)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		puzzle_grid.add_child(empty_label)

	for puzzle_data in puzzles_to_show:
		var puzzle_button: Button = Button.new()
		var button_text: String = str(puzzle_data.get("name", "Untitled"))
		var tier: String = str(puzzle_data.get("difficulty_tier", "medium"))
		var stars: String = "★★☆"
		if tier == "easy":
			stars = "★☆☆"
		elif tier == "hard":
			stars = "★★★"
		var time_seconds: int = int(puzzle_data.get("par_time_seconds", 120))
		button_text += "\n" + stars + " | " + str(time_seconds) + "s"
		puzzle_button.text = button_text
		puzzle_button.custom_minimum_size = Vector2(0.0, 64.0)
		puzzle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		puzzle_button.clip_text = true
		puzzle_button.tooltip_text = str(puzzle_data.get("name", "Untitled"))
		puzzle_button.focus_mode = Control.FOCUS_ALL
		puzzle_button.add_theme_font_size_override("font_size", 16)
		puzzle_button.add_theme_stylebox_override("normal", btn_normal)
		puzzle_button.add_theme_stylebox_override("hover", btn_hover)
		puzzle_button.add_theme_stylebox_override("pressed", btn_hover)
		puzzle_button.pressed.connect(_on_puzzle_selected.bind(puzzle_data))
		puzzle_grid.add_child(puzzle_button)

	_apply_responsive_layout()


func _on_puzzle_selected(puzzle_data: Dictionary) -> void:
	_switch_mode(GameManagerClass.GameMode.VOXEL_LOGIC, {"custom_puzzle": puzzle_data})


func _on_back_pressed() -> void:
	_switch_mode(GameManagerClass.GameMode.MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _switch_mode(mode: int, payload: Dictionary = {}) -> void:
	var game_manager: Node = _get_game_manager()
	if game_manager and game_manager.has_method("switch_mode"):
		game_manager.call("switch_mode", mode, payload)


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
	var compact: bool = viewport_size.x < 600.0 or viewport_size.y < 560.0 or available_height < 560.0
	var horizontal_margin: float = 12.0 if compact else 28.0
	var top_margin: float = 64.0 if compact else 108.0
	var bottom_margin: float = 60.0 if compact else 84.0
	var separation: float = 10.0 if compact else 24.0

	if content:
		content.anchor_left = 0.0
		content.anchor_top = 0.0
		content.anchor_right = 1.0
		content.anchor_bottom = 1.0
		content.offset_left = insets.x + horizontal_margin
		content.offset_top = insets.y + top_margin
		content.offset_right = -(insets.z + horizontal_margin)
		content.offset_bottom = -(insets.w + bottom_margin)
		content.add_theme_constant_override("separation", int(separation))

	var category_width: float = clampf(available_width * (0.34 if compact else 0.25), 96.0, 220.0)
	category_width = minf(category_width, maxf(80.0, available_width * 0.42))
	if category_panel:
		category_panel.custom_minimum_size = Vector2(category_width, 0.0)
		category_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		category_panel.add_theme_constant_override("separation", 8 if compact else 12)
	if category_list:
		category_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		category_list.add_theme_constant_override("separation", 2 if compact else 10)
		for child in category_list.get_children():
			if child is Button:
				var category_button: Button = child as Button
				category_button.custom_minimum_size = Vector2(0.0, 44.0 if compact else 48.0)
	if puzzle_panel:
		puzzle_panel.custom_minimum_size = Vector2(0.0, 0.0)
		puzzle_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		puzzle_panel.add_theme_constant_override("separation", 8 if compact else 14)
	if puzzle_scroll:
		puzzle_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		puzzle_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if puzzle_grid:
		puzzle_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		puzzle_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
		puzzle_grid.add_theme_constant_override("h_separation", 8 if compact else 14)
		puzzle_grid.add_theme_constant_override("v_separation", 8 if compact else 14)
		var puzzle_width: float = maxf(1.0, available_width - category_width - separation)
		var columns: int = 1 if puzzle_width < 230.0 else 2 if puzzle_width < 460.0 else 3
		puzzle_grid.columns = columns
		for child in puzzle_grid.get_children():
			if child is Button:
				var puzzle_button: Button = child as Button
				puzzle_button.custom_minimum_size = Vector2(0.0, 64.0 if compact else 76.0)
				puzzle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if title:
		title.anchor_left = 0.0
		title.anchor_right = 1.0
		title.anchor_top = 0.0
		title.anchor_bottom = 0.0
		title.offset_left = insets.x + 12.0
		title.offset_right = -(insets.z + 12.0)
		title.offset_top = insets.y + (10.0 if compact else 28.0)
		title.offset_bottom = title.offset_top + (42.0 if compact else 56.0)
		title.add_theme_font_size_override("font_size", 28 if compact else 40)
		title.clip_text = true

	if back_button:
		back_button.anchor_left = 0.5
		back_button.anchor_right = 0.5
		back_button.anchor_top = 1.0
		back_button.anchor_bottom = 1.0
		var back_width: float = minf(220.0, maxf(120.0, available_width - 24.0))
		back_button.offset_left = -back_width * 0.5
		back_button.offset_right = back_width * 0.5
		back_button.offset_top = -bottom_margin + 4.0
		back_button.offset_bottom = -insets.w - 8.0
		back_button.custom_minimum_size = Vector2(0.0, 48.0)
		back_button.focus_mode = Control.FOCUS_ALL


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
