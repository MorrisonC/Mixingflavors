extends Node
class_name ComboTimeBonusMechanic

@export var is_enabled: bool = true
@export var combo_threshold: int = 5
@export var time_bonus: float = 5.0

var grid_manager: Node3D

func _ready():
	grid_manager = get_parent()
	if grid_manager and grid_manager.has_signal("combo_updated"):
		grid_manager.combo_updated.connect(_on_combo_updated)

func _on_combo_updated(current_combo: int):
	if not is_enabled or not grid_manager:
		return

	if current_combo > 0 and current_combo % combo_threshold == 0:
		var root = grid_manager.get_parent()
		if root and root.name == "EscapeGauntlet" and "time_left" in root:
			root.time_left += time_bonus
