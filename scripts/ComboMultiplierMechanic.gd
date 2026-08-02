extends Node
class_name ComboMultiplierMechanic

@export var is_enabled: bool = true
@export var combo_thresholds: Array[int] = [5, 10, 15, 20]
@export var multiplier_values: Array[float] = [1.5, 2.0, 3.0, 5.0]

signal multiplier_changed(new_multiplier: float)

var grid_manager: Node3D
var current_multiplier: float = 1.0

func _ready():
	grid_manager = get_parent()
	if grid_manager and grid_manager.has_signal("combo_updated"):
		grid_manager.combo_updated.connect(_on_combo_updated)

func _on_combo_updated(current_combo: int):
	if not is_enabled:
		return

	var new_multiplier: float = 1.0
	for i in range(combo_thresholds.size()):
		if current_combo >= combo_thresholds[i]:
			if i < multiplier_values.size():
				new_multiplier = multiplier_values[i]

	if new_multiplier != current_multiplier:
		current_multiplier = new_multiplier
		multiplier_changed.emit(current_multiplier)
