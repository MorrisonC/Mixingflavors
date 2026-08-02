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
			var old_hp = grid_manager.player_hp
			grid_manager.player_hp = min(grid_manager.player_hp + heal_amount, max_hp)
			if grid_manager.has_method("_update_ui_state"):
				grid_manager._update_ui_state()

			if old_hp < grid_manager.player_hp and grid_manager.get("hp_label") != null:
				var hp_label = grid_manager.hp_label
				hp_label.pivot_offset = hp_label.size / 2
				var tween = create_tween()
				tween.set_parallel(true)
				tween.tween_property(hp_label, "modulate", Color(0, 1, 0, 1), 0.1) # Flash green
				tween.tween_property(hp_label, "scale", Vector2(1.5, 1.5), 0.1)
				tween.chain().tween_property(hp_label, "modulate", Color(1, 1, 1, 1), 0.2)
				tween.parallel().tween_property(hp_label, "scale", Vector2(1, 1), 0.2)
