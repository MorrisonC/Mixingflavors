extends Node
class_name ComboHealMechanic

@export var is_enabled: bool = true
@export var combo_threshold: int = 10
@export var heal_amount: int = 1

var grid_manager: Node3D

func _ready():
	grid_manager = get_parent()
	if grid_manager and grid_manager.has_signal("combo_updated"):
		grid_manager.combo_updated.connect(_on_combo_updated)

func _on_combo_updated(current_combo: int):
	if not is_enabled or not grid_manager:
		return

	if current_combo > 0 and current_combo % combo_threshold == 0:
		var max_hp = 3
		# Try to find max_hp in gauntlet mode if we have access to it
		var root = grid_manager.get_parent()
		if root and root.name == "EscapeGauntlet" and "max_mistakes" in root:
			max_hp = root.max_mistakes

		if grid_manager.player_hp < max_hp:
			grid_manager.player_hp = min(grid_manager.player_hp + heal_amount, max_hp)
			if grid_manager.has_method("_update_ui_state"):
				grid_manager._update_ui_state()
