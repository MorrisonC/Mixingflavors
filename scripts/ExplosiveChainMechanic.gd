extends Node

@export var blast_radius: int = 1
@export var is_active: bool = false

var _grid_manager: Node = null

func _ready() -> void:
	# Assume the parent is the GridManager
	_grid_manager = get_parent()
	if _grid_manager and _grid_manager.has_signal("voxel_destroyed"):
		_grid_manager.connect("voxel_destroyed", _on_voxel_destroyed)

func _on_voxel_destroyed(pos: Vector3i, is_player_action: bool) -> void:
	if not is_active:
		return

	# Only trigger the chain on direct player actions to avoid infinite loops
	if not is_player_action:
		return

	# Trigger a chain reaction for adjacent blocks
	var adjacent_offsets = [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1)
	]

	# Iterate up to the blast radius
	for i in range(1, blast_radius + 1):
		for offset in adjacent_offsets:
			var adj_pos = pos + (offset * i)

			# If the position is within the grid and valid, chisel it as a non-player action
			if _grid_manager.has_method("on_chisel_requested"):
				_grid_manager.on_chisel_requested(adj_pos, false)
