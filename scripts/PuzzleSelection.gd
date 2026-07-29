extends Control

const GameManagerClass = preload("res://scripts/GameManager.gd")

@onready var category_list: VBoxContainer = $HBoxContainer/CategoryPanel/CategoryList
@onready var puzzle_grid: GridContainer = $HBoxContainer/PuzzlePanel/ScrollContainer/PuzzleGrid
@onready var back_button: Button = $BackButton

# Predefined collections matching nathsou's categories
var collections: Dictionary = {
	"Tutorials": ["res://assets/puzzles/tutorial/simple_hints.json"],
	"Animals": ["res://assets/puzzles/animals/horse.json", "res://assets/puzzles/animals/platypus.json", "res://assets/puzzles/animals/suzanne.json"],
	"Furniture": ["res://assets/puzzles/furniture/chair.json", "res://assets/puzzles/furniture/computer.json"],
	"Egypt": ["res://assets/puzzles/egypt/pyramid.json", "res://assets/puzzles/egypt/sphinx.json"],
	"Nature": ["res://assets/puzzles/nature/strange_tree.json"]
}

var btn_normal: StyleBoxFlat
var btn_hover: StyleBoxFlat

func _ready() -> void:
	# Define styles for buttons
	btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.95, 0.45, 0.55, 1)
	btn_normal.corner_radius_top_left = 8
	btn_normal.corner_radius_top_right = 8
	btn_normal.corner_radius_bottom_right = 8
	btn_normal.corner_radius_bottom_left = 8
	btn_normal.shadow_color = Color(0.8, 0.2, 0.3, 0.3)
	btn_normal.shadow_size = 3
	btn_normal.shadow_offset = Vector2(0, 3)

	btn_hover = StyleBoxFlat.new()
	btn_hover.bg_color = Color(1.0, 0.55, 0.65, 1)
	btn_hover.corner_radius_top_left = 8
	btn_hover.corner_radius_top_right = 8
	btn_hover.corner_radius_bottom_right = 8
	btn_hover.corner_radius_bottom_left = 8
	btn_hover.shadow_color = Color(0.8, 0.2, 0.3, 0.2)
	btn_hover.shadow_size = 1
	btn_hover.shadow_offset = Vector2(0, 1)

	back_button.pressed.connect(_on_back_pressed)

	_build_category_menu()
	# Load Tutorials by default
	_load_category("Tutorials")

func _build_category_menu() -> void:
	for cat in collections.keys():
		var btn = Button.new()
		btn.text = cat
		btn.custom_minimum_size = Vector2(0, 50)
		btn.add_theme_font_size_override("font_size", 20)
		btn.add_theme_stylebox_override("normal", btn_normal)
		btn.add_theme_stylebox_override("hover", btn_hover)
		btn.add_theme_stylebox_override("pressed", btn_hover)
		btn.pressed.connect(func(): _load_category(cat))
		category_list.add_child(btn)

func _load_category(category_name: String) -> void:
	# Clear old puzzle buttons
	for child in puzzle_grid.get_children():
		child.queue_free()

	var file_paths = collections.get(category_name, [])
	for path in file_paths:
		var file = FileAccess.open(path, FileAccess.READ)
		if file:
			var json_text = file.get_as_text()
			file.close()
			var puzzle_data = JSON.parse_string(json_text)
			if puzzle_data:
				var btn = Button.new()
				btn.text = puzzle_data.get("name", "Untitled")
				btn.custom_minimum_size = Vector2(180, 80)
				btn.add_theme_font_size_override("font_size", 18)
				btn.add_theme_stylebox_override("normal", btn_normal)
				btn.add_theme_stylebox_override("hover", btn_hover)
				btn.add_theme_stylebox_override("pressed", btn_hover)
				btn.pressed.connect(func(): _on_puzzle_selected(puzzle_data))
				puzzle_grid.add_child(btn)

func _on_puzzle_selected(puzzle_data: Dictionary) -> void:
	# Start custom puzzle play mode
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.VOXEL_LOGIC, {"custom_puzzle": puzzle_data})

func _on_back_pressed() -> void:
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.MAIN_MENU)
