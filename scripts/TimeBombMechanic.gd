extends Node
class_name TimeBombMechanic

@export var is_enabled: bool = false
@export_range(1.0, 120.0, 0.5) var bomb_duration: float = 10.0
@export_range(1.0, 120.0, 0.5) var bomb_spawn_interval: float = 15.0
@export var bomb_color: Color = Color(1.0, 0.2, 0.2)

var grid_manager: GridManager
var active_bomb_pos: Vector3i = Vector3i(-1, -1, -1)
var bomb_timer: float = 0.0
var spawn_timer: float = 0.0

func _ready() -> void:
	grid_manager = get_parent() as GridManager
	if is_instance_valid(grid_manager):
		if not grid_manager.block_destroyed.is_connected(_on_block_destroyed):
			grid_manager.block_destroyed.connect(_on_block_destroyed)
		if not grid_manager.floor_cleared.is_connected(_on_floor_cleared):
			grid_manager.floor_cleared.connect(_on_floor_cleared)

func _process(delta: float) -> void:
	if not is_enabled or not is_instance_valid(grid_manager) or not grid_manager.is_puzzle_active or grid_manager.input_locked:
		return
	if active_bomb_pos.x < 0:
		spawn_timer += delta
		if spawn_timer >= bomb_spawn_interval:
			_spawn_bomb()
		return

	bomb_timer -= delta
	var block := grid_manager.blocks.get(active_bomb_pos) as VoxelBlock
	if not is_instance_valid(block) or not grid_manager.is_cell_unbroken(active_bomb_pos):
		_reset_bomb()
		return
	var pulse: float = (sin(bomb_timer * 12.0) + 1.0) * 0.5
	block.base_material.albedo_color = block.default_color.lerp(bomb_color, pulse)
	if bomb_timer <= 0.0:
		_explode_bomb()

func _spawn_bomb() -> void:
	if not is_instance_valid(grid_manager):
		return
	var valid_positions: Array[Vector3i] = []
	for pos: Vector3i in grid_manager.voxel_states.keys():
		if grid_manager.is_target_cell(pos) or not grid_manager.is_cell_unbroken(pos):
			continue
		if grid_manager.voxel_states[pos].get("is_hidden_by_slice", false):
			continue
		valid_positions.append(pos)
	if valid_positions.is_empty():
		spawn_timer = 0.0
		return
	active_bomb_pos = valid_positions[randi() % valid_positions.size()]
	bomb_timer = bomb_duration
	spawn_timer = 0.0

func _explode_bomb() -> void:
	if is_instance_valid(grid_manager) and grid_manager.voxel_states.has(active_bomb_pos):
		var block := grid_manager.blocks.get(active_bomb_pos) as VoxelBlock
		var previous_state: int = int(grid_manager.voxel_states[active_bomb_pos].get("cell_state", GridManager.CellState.UNBROKEN))
		grid_manager.record_move(active_bomb_pos, previous_state)
		grid_manager.is_player_action = false
		var destroyed: bool = grid_manager.destroy_block(block)
		grid_manager.is_player_action = true
		if destroyed:
			grid_manager._handle_mistake()
		else:
			grid_manager.move_history.pop_back()
	_reset_bomb()

func _reset_bomb() -> void:
	if is_instance_valid(grid_manager) and grid_manager.blocks.has(active_bomb_pos):
		var block := grid_manager.blocks[active_bomb_pos] as VoxelBlock
		if is_instance_valid(block) and block.current_state == block.BlockState.UNBROKEN:
			block.base_material.albedo_color = block.default_color
	active_bomb_pos = Vector3i(-1, -1, -1)
	bomb_timer = 0.0
	spawn_timer = 0.0

func _on_block_destroyed(pos: Vector3i, _is_player_action: bool) -> void:
	if pos == active_bomb_pos:
		_reset_bomb()

func _on_floor_cleared() -> void:
	_reset_bomb()
