extends Node

# Signal emitted when switching game modes or updating stats
signal mode_changed(new_mode_id)
signal stat_changed(stat_name, new_value)

# GameMode Identifiers
enum GameMode {
	MAIN_MENU,
	VOXEL_LOGIC,
	ESCAPE_GAUNTLET,
	PUZZLE_EDITOR,
	PUZZLE_SELECTION,
	MASQUERADE_PAINTING
}

signal theme_changed(is_valentine)

var _valentine_theme_active: bool = false
var tutorial_completed: bool = false
var mode_payload: Dictionary = {}

# Core RPG Stats
var stats: Dictionary = {
	"perception": 2,
	"health": 100,
	"endurance": 100,
	"alchemy_discipline": 2,
	"lore_discipline": 1
}

# Cross-Mechanic Data Buffer (Passes state between modes)
var active_voxel_template: Array = []
var discovered_anchors: Array = []
var current_mode: GameMode = GameMode.MAIN_MENU
var selected_difficulty_mode: String = "medium"

# Scene File Paths (Ensure case-sensitivity matches your project files)
const MODE_SCENES: Dictionary = {
	GameMode.MAIN_MENU: "res://scenes/MainMenu.tscn",
	GameMode.VOXEL_LOGIC: "res://scenes/VoxelLogic.tscn",
	GameMode.ESCAPE_GAUNTLET: "res://scenes/EscapeGauntlet.tscn",
	GameMode.PUZZLE_EDITOR: "res://scenes/PuzzleEditor.tscn",
	GameMode.PUZZLE_SELECTION: "res://scenes/PuzzleSelection.tscn"
}

func _ready() -> void:
	load_settings()
	print("[GameManager] Initialized successfully. Current Mode: MainMenu")

func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	if err == OK:
		tutorial_completed = config.get_value("Progress", "tutorial_completed", false)

func save_settings() -> void:
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("Progress", "tutorial_completed", tutorial_completed)
	config.save("user://settings.cfg")

func set_stat(stat_name: String, value: int) -> void:
	if stats.has(stat_name):
		stats[stat_name] = value
		emit_signal("stat_changed", stat_name, value)
		print("[GameManager] Stat updated: ", stat_name, " = ", value)

func get_stat(stat_name: String) -> int:
	return stats.get(stat_name, 0)

static func is_valentine_theme() -> bool:
	var gm = Engine.get_main_loop().root.get_node_or_null("GameManager")
	if gm:
		return gm._valentine_theme_active
	return false

func set_valentine_theme(active: bool) -> void:
	if _valentine_theme_active != active:
		_valentine_theme_active = active
		emit_signal("theme_changed", active)

# Main Scene-Switching Logic
func switch_mode(target_mode: GameMode, payload: Dictionary = {}) -> void:
	current_mode = target_mode
	mode_payload = payload

	# Process cross-mechanic payload if passed
	if payload.has("voxel_template"):
		active_voxel_template = payload["voxel_template"]
	if payload.has("anchors"):
		discovered_anchors = payload["anchors"]

	emit_signal("mode_changed", target_mode)
	print("[GameManager] Switched to mode: ", target_mode)
