extends Node

# Signal emitted when switching game modes or updating stats
signal mode_changed(new_mode_id)
signal stat_changed(stat_name, new_value)

# GameMode Identifiers as defined in Master Level Design
enum GameMode {
	LONE_WOLF_NARRATIVE,
	MASQUERADE_PAINTING,
	PICROSS_3D,
	DETECTIVE_CRIME_SCENE,
	ESCAPE_GAUNTLET,
	TIME_SHIFT_PALIMPSEST
}

# Core RPG Stats
var stats: Dictionary = {
	"perception": 2,          # Unlocks hidden anchors in MasqueradePainting if > 1
	"health": 100,            # High health prevents Picross3D corruption (> 50)
	"endurance": 100,         # High endurance prevents Picross3D corruption (> 50)
	"alchemy_discipline": 2,  # Allows custom voxel coloring/solving advanced constraints (> 1)
	"lore_discipline": 1      # Unlocks additional narrative dialogue options
}

# Cross-Mechanic Data Buffer (Passes state between modes)
var active_voxel_template: Array = []
var discovered_anchors: Array = []
var current_mode: GameMode = GameMode.LONE_WOLF_NARRATIVE

# Scene File Paths (Ensure case-sensitivity matches your project files)
const MODE_SCENES: Dictionary = {
	GameMode.LONE_WOLF_NARRATIVE: "res://scenes/LoneWolfNarrative.tscn",
	GameMode.MASQUERADE_PAINTING: "res://scenes/MasqueradePainting.tscn",
	GameMode.PICROSS_3D: "res://scenes/Picross3D.tscn"
}

func _ready() -> void:
	print("[GameManager] Initialized successfully. Current Mode: LoneWolfNarrative")

func set_stat(stat_name: String, value: int) -> void:
	if stats.has(stat_name):
		stats[stat_name] = value
		emit_signal("stat_changed", stat_name, value)
		print("[GameManager] Stat updated: ", stat_name, " = ", value)

func get_stat(stat_name: String) -> int:
	return stats.get(stat_name, 0)

# Main Scene-Switching Logic
func switch_mode(target_mode: GameMode, payload: Dictionary = {}) -> void:
	current_mode = target_mode

	# Process cross-mechanic payload if passed
	if payload.has("voxel_template"):
		active_voxel_template = payload["voxel_template"]
	if payload.has("anchors"):
		discovered_anchors = payload["anchors"]

	emit_signal("mode_changed", target_mode)
	print("[GameManager] Switched to mode: ", target_mode)
