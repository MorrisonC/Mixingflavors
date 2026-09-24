extends Node
class_name CooldownHintMechanic

@export var is_enabled: bool = true
@export_range(0.0, 120.0, 0.5) var cooldown_duration: float = 10.0

var grid_manager: GridManager
var is_ready: bool = true
var _cooldown_timer: float = 0.0

signal hint_ready
signal hint_used(grid_pos: Vector3i, action_type: String)
signal cooldown_updated(time_left: float)

func _ready() -> void:
	grid_manager = get_parent() as GridManager
	set_process(true)

func _process(delta: float) -> void:
	if not is_enabled or is_ready:
		return
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	if _cooldown_timer <= 0.0:
		is_ready = true
		hint_ready.emit()
	else:
		cooldown_updated.emit(_cooldown_timer)

func get_cooldown_remaining() -> float:
	return 0.0 if is_ready else _cooldown_timer

func use_hint() -> bool:
	if not is_enabled or not is_ready or not is_instance_valid(grid_manager):
		return false
	if not grid_manager.is_puzzle_active or grid_manager.input_locked:
		return false

	var found_pos := Vector3i(-1, -1, -1)
	var found_is_target: bool = false
	for pos: Vector3i in grid_manager.voxel_states.keys():
		if not grid_manager.is_cell_unbroken(pos):
			continue
		if grid_manager.voxel_states[pos].get("is_hidden_by_slice", false):
			continue
		found_pos = pos
		found_is_target = grid_manager.is_target_cell(pos)
		break
	if found_pos.x < 0:
		return false

	var previous_state: int = int(grid_manager.voxel_states[found_pos].get("cell_state", GridManager.CellState.UNBROKEN))
	grid_manager.record_move(found_pos, previous_state)
	grid_manager.is_player_action = false
	var used_successfully: bool = false
	if found_is_target:
		used_successfully = grid_manager.mark_cell(found_pos)
		if used_successfully:
			hint_used.emit(found_pos, "mark")
	else:
		var block := grid_manager.blocks.get(found_pos) as VoxelBlock
		used_successfully = grid_manager.destroy_block(block)
		if used_successfully:
			hint_used.emit(found_pos, "destroy")
	grid_manager.is_player_action = true

	if not used_successfully:
		grid_manager.move_history.pop_back()
		grid_manager.history_updated.emit(not grid_manager.move_history.is_empty())
		return false
	is_ready = false
	_cooldown_timer = cooldown_duration
	cooldown_updated.emit(_cooldown_timer)
	return true
