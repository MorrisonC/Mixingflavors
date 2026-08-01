extends Node
class_name TimeBombMechanic

@export var is_enabled: bool = true
@export var bomb_duration: float = 10.0
@export var bomb_spawn_interval: float = 15.0
@export var bomb_color: Color = Color(1.0, 0.2, 0.2)

var grid_manager: Node3D
var active_bomb_pos: Vector3i = Vector3i(-1, -1, -1)
var bomb_timer: float = 0.0
var spawn_timer: float = 0.0

func _ready():
	grid_manager = get_parent()
	if grid_manager:
		if grid_manager.has_signal("block_destroyed") and not grid_manager.block_destroyed.is_connected(_on_block_destroyed):
			grid_manager.block_destroyed.connect(_on_block_destroyed)
		if grid_manager.has_signal("floor_cleared") and not grid_manager.floor_cleared.is_connected(_on_floor_cleared):
			grid_manager.floor_cleared.connect(_on_floor_cleared)

func _process(delta: float):
	if not is_enabled or not grid_manager:
		return

	# Only process if puzzle is active
	if not grid_manager.get("is_puzzle_active"):
		return

	if active_bomb_pos == Vector3i(-1, -1, -1):
		spawn_timer += delta
		if spawn_timer >= bomb_spawn_interval:
			_spawn_bomb()
	else:
		bomb_timer -= delta

		if grid_manager.blocks.has(active_bomb_pos):
			var block = grid_manager.blocks[active_bomb_pos]
			if block.current_state == block.BlockState.UNBROKEN:
				# Flash effect: alternate between default and bomb_color
				var pulse = (sin(bomb_timer * 12.0) + 1.0) / 2.0
				block.base_material.albedo_color = block.default_color.lerp(bomb_color, pulse)
			else:
				# If state changed without being destroyed (e.g. hidden by slice), reset
				_reset_bomb()
				return

		if bomb_timer <= 0.0:
			_explode_bomb()

func _spawn_bomb():
	if not grid_manager or not grid_manager.get("blocks"):
		return

	var valid_positions = []
	var blocks = grid_manager.blocks
	var target_shape = grid_manager.target_shape

	for pos in blocks.keys():
		var block = blocks[pos]
		# Find unbroken blocks that are NOT part of the solution
		if block.current_state == block.BlockState.UNBROKEN and not (pos in target_shape):
			# Ensure it's not hidden by the slicing tool
			if pos.x <= grid_manager.slice_max.x and pos.y <= grid_manager.slice_max.y and pos.z <= grid_manager.slice_max.z:
				valid_positions.append(pos)

	if valid_positions.size() > 0:
		active_bomb_pos = valid_positions[randi() % valid_positions.size()]
		bomb_timer = bomb_duration
		spawn_timer = 0.0

func _explode_bomb():
	if grid_manager and grid_manager.blocks.has(active_bomb_pos):
		var block = grid_manager.blocks[active_bomb_pos]
		if block.current_state == block.BlockState.UNBROKEN:
			grid_manager.is_player_action = false
			# Destroy the block and trigger a mistake penalty
			grid_manager._destroy_block(block)
			grid_manager._handle_mistake()
			grid_manager.is_player_action = true

	_reset_bomb()

func _reset_bomb():
	if active_bomb_pos != Vector3i(-1, -1, -1) and grid_manager.blocks.has(active_bomb_pos):
		var block = grid_manager.blocks[active_bomb_pos]
		# Restore original color if still unbroken
		if block.current_state == block.BlockState.UNBROKEN:
			block.base_material.albedo_color = block.default_color

	active_bomb_pos = Vector3i(-1, -1, -1)
	spawn_timer = 0.0

func _on_block_destroyed(pos: Vector3i, is_player_action: bool):
	if pos == active_bomb_pos:
		# Player successfully defused (destroyed) the bomb block
		_reset_bomb()

func _on_floor_cleared():
	_reset_bomb()
