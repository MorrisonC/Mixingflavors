extends Node
class_name ExplosiveChainMechanic

@export var is_enabled: bool = false
@export_range(1, 16, 1) var max_chain_distance: int = 8

var grid_manager: GridManager

func _ready() -> void:
	grid_manager = get_parent() as GridManager
	if grid_manager and not grid_manager.block_destroyed.is_connected(_on_block_destroyed):
		grid_manager.block_destroyed.connect(_on_block_destroyed)

func _on_block_destroyed(pos: Vector3i, is_player_action: bool) -> void:
	if not is_enabled or not is_player_action or not is_instance_valid(grid_manager):
		return
	if not grid_manager.is_puzzle_active or grid_manager.input_locked:
		return

	var batch: Array = []
	if not grid_manager.move_history.is_empty():
		batch.append(grid_manager.move_history.pop_back())
	grid_manager.is_player_action = false

	for axis: Vector3i in [Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1)]:
		var line_length: int = 0
		var line_start := Vector3i.ZERO
		match axis:
			Vector3i(1, 0, 0):
				line_length = grid_manager.grid_size.x
				line_start = Vector3i(0, pos.y, pos.z)
			Vector3i(0, 1, 0):
				line_length = grid_manager.grid_size.y
				line_start = Vector3i(pos.x, 0, pos.z)
			Vector3i(0, 0, 1):
				line_length = grid_manager.grid_size.z
				line_start = Vector3i(pos.x, pos.y, 0)
		line_length = mini(line_length, max_chain_distance)

		if not grid_manager._calculate_clue(line_start, axis, line_length).is_empty():
			continue

		for index: int in range(line_length):
			var cell_pos: Vector3i = line_start + axis * index
			if not grid_manager.is_cell_unbroken(cell_pos):
				continue
			if grid_manager.voxel_states[cell_pos].get("is_hidden_by_slice", false):
				continue
			var move := {
				"pos": cell_pos,
				"state": GridManager.CellState.UNBROKEN,
				"target": grid_manager.is_target_cell(cell_pos)
			}
			batch.append(move)
			grid_manager.hammer_cell(cell_pos)

	grid_manager.is_player_action = true
	if batch.size() > 1:
		grid_manager.move_history.append(batch)
		grid_manager.history_updated.emit(true)
		grid_manager._update_clues()
		grid_manager._update_ui_state()
