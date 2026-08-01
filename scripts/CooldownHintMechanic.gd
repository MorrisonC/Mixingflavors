extends Node
class_name CooldownHintMechanic

@export var is_enabled: bool = true
@export var cooldown_duration: float = 10.0

var grid_manager: Node3D
var is_ready: bool = true
var _cooldown_timer: float = 0.0

signal hint_ready
signal hint_used(grid_pos: Vector3i, action_type: String)
signal cooldown_updated(time_left: float)

func _ready() -> void:
	grid_manager = get_parent()
	set_process(true)

func _process(delta: float) -> void:
	if not is_enabled:
		return

	if not is_ready:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			_cooldown_timer = 0.0
			is_ready = true
			emit_signal("hint_ready")
		else:
			emit_signal("cooldown_updated", _cooldown_timer)

func use_hint() -> bool:
	if not is_enabled or not is_ready or not grid_manager:
		return false

	# Look for an unbroken block that we can safely resolve
	var blocks = grid_manager.blocks
	var target_shape = grid_manager.target_shape

	# Priority 1: Find a target block that is UNBROKEN and mark it (since there is no PAINTED state in the test, let's mark it)
	var found_pos = Vector3i(-1, -1, -1)
	var found_block = null
	var is_target = false

	for pos in blocks.keys():
		var block = blocks[pos]
		if block.current_state == block.BlockState.UNBROKEN:
			var is_target_block = pos in target_shape
			found_pos = pos
			found_block = block
			is_target = is_target_block
			break

	if found_block == null:
		return false # No hints available (puzzle might be solved or close)

	grid_manager.is_player_action = false
	if is_target:
		grid_manager.record_move(found_pos, found_block.current_state)
		found_block.set_state(found_block.BlockState.MARKED)
		emit_signal("hint_used", found_pos, "mark")
	else:
		grid_manager.record_move(found_pos, found_block.current_state)
		grid_manager.destroy_block(found_block)
		emit_signal("hint_used", found_pos, "destroy")
	grid_manager.is_player_action = true

	is_ready = false
	_cooldown_timer = cooldown_duration

	return true
