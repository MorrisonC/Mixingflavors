extends Node
class_name ExplosiveChainMechanic

@export var is_enabled: bool = false
@export var max_chain_distance: int = 100

var grid_manager: Node3D

func _ready():
	# Find GridManager recursively just in case, but assume parent for now
	grid_manager = get_parent()
	if grid_manager and grid_manager.has_signal("block_destroyed"):
		grid_manager.block_destroyed.connect(_on_block_destroyed)

func _on_block_destroyed(pos: Vector3i, is_player_action: bool):
	if not is_enabled or not is_player_action:
		return

	var chained_moves = []
	var axes = [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)]

	for axis in axes:
		var start = pos
		var i = 0
		while start.x >= 0 and start.y >= 0 and start.z >= 0 and i < max_chain_distance:
			start -= axis
			i += 1
		start += axis

		var length = grid_manager.grid_size.x if axis.x else (grid_manager.grid_size.y if axis.y else grid_manager.grid_size.z)
		length = min(length, max_chain_distance)

		var counts = grid_manager._calculate_clue(start, axis, length)
		if counts.size() == 0:
			# Zero targets on this line, break them all!
			for j in range(length):
				var check_pos = start + axis * j
				if grid_manager.blocks.has(check_pos):
					var check_block = grid_manager.blocks[check_pos]
					if check_block.current_state == check_block.BlockState.UNBROKEN:
						chained_moves.append({"pos": check_pos, "state": check_block.current_state})
						grid_manager.is_player_action = false
						grid_manager.hammer_cell(check_pos)
						grid_manager.destroy_block(check_block)
						grid_manager.is_player_action = true

	if chained_moves.size() > 0:
		# Merge with the last move so they undo together
		if grid_manager.move_history.size() > 0:
			var last = grid_manager.move_history[-1]
			if typeof(last) == TYPE_ARRAY:
				grid_manager.move_history[-1] = last + chained_moves
			else:
				grid_manager.move_history[-1] = [last] + chained_moves
