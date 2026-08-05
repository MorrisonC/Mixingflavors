extends Node
class_name ComboMultiplierMechanic

@export var is_enabled: bool = true
@export var multiplier_increment: float = 0.1
@export var max_multiplier: float = 3.0
@export var combo_threshold: int = 5

var current_multiplier: float = 1.0
var grid_manager: Node3D

func _ready():
	grid_manager = get_parent()
	if grid_manager and grid_manager.has_signal("combo_updated"):
		if not grid_manager.combo_updated.is_connected(_on_combo_updated):
			grid_manager.combo_updated.connect(_on_combo_updated)

func _on_combo_updated(current_combo: int):
	if not is_enabled or not grid_manager:
		return

	if current_combo == 0:
		current_multiplier = 1.0
	elif current_combo > 0 and current_combo % combo_threshold == 0:
		current_multiplier = min(current_multiplier + multiplier_increment, max_multiplier)

	# Apply score/damage multiplier to parent context
	# Note: This is an extensible baseline. The specific scoring system will depend on how the game uses it.
	if grid_manager.has_method("set_combo_multiplier"):
		grid_manager.set_combo_multiplier(current_multiplier)
