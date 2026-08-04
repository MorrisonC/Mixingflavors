extends Node
class_name CrossChiselMechanic

@export var is_enabled: bool = true
@export var combo_threshold: int = 5
@export var cross_radius: int = 1

var grid_manager: Node3D

func _ready():
	grid_manager = get_parent()
	if grid_manager and grid_manager.has_signal("block_destroyed"):
		grid_manager.block_destroyed.connect(_on_block_destroyed)

func _on_block_destroyed(pos: Vector3i, is_player_action: bool):
	if not is_enabled or not is_player_action or not is_instance_valid(grid_manager):
		return

	if grid_manager.combo > 0 and grid_manager.combo % combo_threshold == 0:
		var axes = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
		var chained_moves = []

		for axis in axes:
			for r in range(1, cross_radius + 1):
				var check_pos = pos + axis * r
				if grid_manager.voxel_states.has(check_pos):
					var state = grid_manager.voxel_states[check_pos]
					# Only auto-chisel if it's NOT a target and is UNBROKEN
					if not state.get("is_target", false) and not state.get("is_chiseled", false) and not state.get("is_marked", false) and not state.get("is_painted", false):
						if grid_manager.blocks.has(check_pos):
							var block = grid_manager.blocks[check_pos]
							if block.current_state == block.BlockState.UNBROKEN:
								chained_moves.append({"pos": check_pos, "state": block.current_state})
								# Temporarily disable player action to avoid infinite loops and combo incrementing
								grid_manager.is_player_action = false
								state["is_chiseled"] = true
								grid_manager.destroy_block(block)
								grid_manager.is_player_action = true

		if chained_moves.size() > 0:
			if grid_manager.move_history.size() > 0:
				var last = grid_manager.move_history[-1]
				if typeof(last) == TYPE_ARRAY:
					grid_manager.move_history[-1] = last + chained_moves
				else:
					grid_manager.move_history[-1] = [last] + chained_moves
