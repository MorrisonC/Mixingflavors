extends Node
class_name ExplosiveChainMechanic

@export var combo_threshold: int = 5
@export var explosion_radius: int = 1

var grid_manager: Node

func _ready() -> void:
	grid_manager = get_parent()
	if grid_manager and grid_manager.has_signal("block_destroyed"):
		grid_manager.block_destroyed.connect(_on_block_destroyed)

func _on_block_destroyed(grid_pos: Vector3i, is_player_action: bool) -> void:
	if not is_player_action:
		return

	var combo = grid_manager.get("combo")
	if combo != null and combo > 0 and combo % combo_threshold == 0:
		_trigger_explosion(grid_pos)

func _trigger_explosion(center_pos: Vector3i) -> void:
	# Start a group to ensure all exploded blocks are undone together
	if grid_manager.has_method("start_move_group"):
		grid_manager.start_move_group()

	var offsets = [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1)
	]

	for offset in offsets:
		for i in range(1, explosion_radius + 1):
			var target_pos = center_pos + (offset * i)
			var blocks = grid_manager.get("blocks")

			if blocks and blocks.has(target_pos):
				# Note: on_chisel_requested checks if block is protected, and if it's already destroyed
				# Passing `false` for `is_player_action` prevents recursive explosions and doesn't add to combo
				if grid_manager.has_method("on_chisel_requested"):
					grid_manager.on_chisel_requested(target_pos, false)

	if grid_manager.has_method("end_move_group"):
		grid_manager.end_move_group()
