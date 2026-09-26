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
var _bomb_visual: MeshInstance3D = null

func _ready() -> void:
	grid_manager = get_parent() as GridManager
	if is_instance_valid(grid_manager):
		if not grid_manager.block_destroyed.is_connected(_on_block_destroyed):
			grid_manager.block_destroyed.connect(_on_block_destroyed)
		if not grid_manager.floor_cleared.is_connected(_on_floor_cleared):
			grid_manager.floor_cleared.connect(_on_floor_cleared)

func _process(delta: float) -> void:
	if not is_enabled:
		if is_instance_valid(_bomb_visual) and _bomb_visual.visible:
			_reset_bomb()
		return
	if not is_instance_valid(grid_manager) or not grid_manager.is_puzzle_active or grid_manager.input_locked:
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
	_update_bomb_visual(block, pulse)
	if bomb_timer <= 0.0:
		_explode_bomb()


# Clue hosts are lightweight VoxelBlock nodes and deliberately have no
# per-block material, so the bomb cannot tint a Block material. Draw the single
# active bomb as one reusable overlay instead: one extra node for the whole
# mechanic rather than one per cell.
func _ensure_bomb_visual() -> MeshInstance3D:
	if is_instance_valid(_bomb_visual):
		return _bomb_visual
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.04, 1.04, 1.04)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(bomb_color.r, bomb_color.g, bomb_color.b, 0.35)
	material.emission_enabled = true
	material.emission = bomb_color
	material.emission_energy_multiplier = 1.0
	mesh.surface_set_material(0, material)
	_bomb_visual = MeshInstance3D.new()
	_bomb_visual.mesh = mesh
	_bomb_visual.visible = false
	add_child(_bomb_visual)
	return _bomb_visual


func _update_bomb_visual(block: VoxelBlock, pulse: float) -> void:
	var overlay := _ensure_bomb_visual()
	overlay.position = block.position
	var hidden_by_slice: bool = false
	if grid_manager.voxel_states.has(active_bomb_pos):
		hidden_by_slice = bool(grid_manager.voxel_states[active_bomb_pos].get("is_hidden_by_slice", false))
	overlay.visible = not hidden_by_slice
	var material := overlay.mesh.surface_get_material(0) as StandardMaterial3D
	if material != null:
		material.albedo_color = Color(bomb_color.r, bomb_color.g, bomb_color.b, 0.25 + pulse * 0.45)
		material.emission_energy_multiplier = 0.6 + pulse * 1.8


func _hide_bomb_visual() -> void:
	if is_instance_valid(_bomb_visual):
		_bomb_visual.visible = false

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
	# Show the pulse on the spawn frame instead of waiting for the next tick.
	var spawned_block: VoxelBlock = grid_manager.blocks.get(active_bomb_pos) as VoxelBlock
	if is_instance_valid(spawned_block):
		_update_bomb_visual(spawned_block, 0.0)

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
	_hide_bomb_visual()
	active_bomb_pos = Vector3i(-1, -1, -1)
	bomb_timer = 0.0
	spawn_timer = 0.0

func _on_block_destroyed(pos: Vector3i, _is_player_action: bool) -> void:
	if pos == active_bomb_pos:
		_reset_bomb()

func _on_floor_cleared() -> void:
	_reset_bomb()
