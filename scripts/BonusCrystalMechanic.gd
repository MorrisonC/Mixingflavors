extends Node
class_name BonusCrystalMechanic

@export var is_enabled: bool = true
@export var crystal_spawn_interval: float = 20.0
@export var crystal_duration: float = 10.0
@export var crystal_color: Color = Color(0.2, 0.8, 1.0)
@export var bonus_combo: int = 5

var grid_manager: Node3D
var active_crystal_pos: Vector3i = Vector3i(-1, -1, -1)
var crystal_timer: float = 0.0
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

	if active_crystal_pos == Vector3i(-1, -1, -1):
		spawn_timer += delta
		if spawn_timer >= crystal_spawn_interval:
			_spawn_crystal()
	else:
		crystal_timer -= delta

		if grid_manager.blocks.has(active_crystal_pos):
			var block = grid_manager.blocks[active_crystal_pos]
			if block.current_state == block.BlockState.UNBROKEN:
				# Pulsing effect for the crystal
				var pulse = (sin(crystal_timer * 8.0) + 1.0) / 2.0
				block.base_material.albedo_color = block.default_color.lerp(crystal_color, pulse)
			else:
				# If state changed without being destroyed (e.g. hidden by slice), reset
				_reset_crystal()
				return

		if crystal_timer <= 0.0:
			_expire_crystal()

func _spawn_crystal():
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
		active_crystal_pos = valid_positions[randi() % valid_positions.size()]
		crystal_timer = crystal_duration
		spawn_timer = 0.0

func _expire_crystal():
	# The crystal simply disappears when the timer expires, no penalty
	_reset_crystal()

func _reset_crystal():
	if active_crystal_pos != Vector3i(-1, -1, -1) and grid_manager.blocks.has(active_crystal_pos):
		var block = grid_manager.blocks[active_crystal_pos]
		# Restore original color if still unbroken
		if block.current_state == block.BlockState.UNBROKEN:
			block.base_material.albedo_color = block.default_color

	active_crystal_pos = Vector3i(-1, -1, -1)
	spawn_timer = 0.0

func _on_block_destroyed(pos: Vector3i, is_player_action: bool):
	if pos == active_crystal_pos:
		# Player successfully chiseled the crystal block!
		if is_player_action:
			grid_manager.combo += bonus_combo
			if grid_manager.has_method("_update_ui_state"):
				grid_manager._update_ui_state()
			if grid_manager.has_signal("combo_updated"):
				grid_manager.emit_signal("combo_updated", grid_manager.combo)

			if grid_manager.get("combo_label"):
				var label = grid_manager.combo_label
				label.pivot_offset = label.size / 2
				var tween = create_tween()
				tween.set_parallel(true)
				tween.tween_property(label, "modulate", crystal_color, 0.1)
				tween.tween_property(label, "scale", Vector2(1.8, 1.8), 0.1)
				tween.chain().tween_property(label, "modulate", Color(1, 1, 1, 1), 0.3)
				tween.parallel().tween_property(label, "scale", Vector2(1, 1), 0.3)

		_reset_crystal()

func _on_floor_cleared():
	_reset_crystal()
