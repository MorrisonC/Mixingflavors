extends Node
class_name ComboHealMechanic

@export var is_enabled: bool = true
@export_range(2, 100, 1) var combo_threshold: int = 10
@export_range(1, 5, 1) var heal_amount: int = 1

var grid_manager: GridManager

func _ready() -> void:
	grid_manager = get_parent() as GridManager
	if grid_manager and not grid_manager.combo_updated.is_connected(_on_combo_updated):
		grid_manager.combo_updated.connect(_on_combo_updated)

func _on_combo_updated(current_combo: int) -> void:
	if not is_enabled or not is_instance_valid(grid_manager) or combo_threshold <= 0:
		return
	if current_combo <= 0 or current_combo % combo_threshold != 0:
		return

	var max_hp: int = 3
	var round_owner := grid_manager.get_parent()
	if round_owner and "max_mistakes" in round_owner:
		max_hp = int(round_owner.get("max_mistakes"))
	if grid_manager.player_hp < max_hp:
		grid_manager.player_hp = mini(grid_manager.player_hp + heal_amount, max_hp)
		grid_manager._update_ui_state()
