extends Node
class_name VoxelCorruptionMechanic

var grid_manager = null

func _ready() -> void:
	if get_parent() and get_parent().has_method("start_level"):
		grid_manager = get_parent()
		grid_manager.mistake_made.connect(_on_mistake_made)

func _on_mistake_made(total_mistakes: int) -> void:
	if not is_instance_valid(grid_manager): return
	if not grid_manager.is_puzzle_active: return

	# Determine if health < 50%
	var max_hp = 3
	var gauntlet = grid_manager.get_parent()
	if gauntlet and "max_mistakes" in gauntlet:
		max_hp = gauntlet.max_mistakes

	var current_hp = grid_manager.player_hp
	var hp_percentage = float(current_hp) / float(max_hp)

	if hp_percentage < 0.5:
		_corrupt_random_voxels(1)

func _corrupt_random_voxels(count: int) -> void:
	var candidates = []
	for pos in grid_manager.voxel_states.keys():
		var state = grid_manager.voxel_states[pos]
		# Find unbroken, un-chiseled, non-target blocks that are not already corrupted
		if not grid_manager.is_cell_chiseled(pos) and not state.get("is_target", false) and not state.get("is_corrupted", false):
			candidates.append(pos)

	if candidates.is_empty():
		return

	candidates.shuffle()

	for i in range(min(count, candidates.size())):
		var pos = candidates[i]
		grid_manager.voxel_states[pos]["is_corrupted"] = true

	# Force multimesh update so the color is rendered
	grid_manager._update_multimesh()
