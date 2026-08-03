extends Node
class_name SolvabilityValidator

# Validates if a given puzzle data (with dims, hints, etc.) can be solved purely by deduction
# returns a boolean
static func is_puzzle_solvable(puzzle_data: Dictionary) -> bool:
	if not puzzle_data.has("dims") or not puzzle_data.has("hints"):
		return false

	var dims = puzzle_data["dims"]
	var dx: int = dims[0]
	var dy: int = dims[1]
	var dz: int = dims[2]

	var hints = puzzle_data["hints"]
	var target_shape = puzzle_data.get("target_voxels", [])

	# State: 0 = Unknown, 1 = Chiseled (Empty), 2 = Target
	var grid_state = {}
	var total_cells = dx * dy * dz

	for x in range(dx):
		for y in range(dy):
			for z in range(dz):
				grid_state[Vector3i(x, y, z)] = 0

	var target_set = {}
	for v in target_shape:
		# puzzle_data might store it as an array or dictionary, ensuring Vector3i
		var v3 = Vector3i(int(v[0]), int(v[1]), int(v[2])) if typeof(v) == TYPE_ARRAY else v
		target_set[v3] = true

	var changed = true
	var max_iterations = total_cells * 2
	var iterations = 0

	while changed and iterations < max_iterations:
		changed = false
		iterations += 1

		# For each line (x, y, z), check if we can deduce anything
		for axis in range(3):
			var a1_max = [dy, dx, dx][axis]
			var a2_max = [dz, dz, dy][axis]

			for a1 in range(a1_max):
				for a2 in range(a2_max):
					var line_clue = _get_line_clue(hints, axis, a1, a2)
					var line_coords = []
					var line_states = []

					var n = [dx, dy, dz][axis]
					for i in range(n):
						var coord
						if axis == 0: coord = Vector3i(i, a1, a2)
						elif axis == 1: coord = Vector3i(a1, i, a2)
						else: coord = Vector3i(a1, a2, i)

						line_coords.append(coord)
						line_states.append(grid_state[coord])

					# Optimization: if already fully solved, skip
					if not line_states.has(0):
						continue

					var valid_configurations = _get_valid_configurations(line_clue, line_states)

					if valid_configurations.is_empty():
						# Invalid puzzle
						return false

					# Check for commonalities among all valid configurations
					for i in range(n):
						if line_states[i] == 0:
							var all_target = true
							var all_empty = true
							for config in valid_configurations:
								if config[i] == 2:
									all_empty = false
								elif config[i] == 1:
									all_target = false

							if all_target:
								grid_state[line_coords[i]] = 2
								changed = true
							elif all_empty:
								grid_state[line_coords[i]] = 1
								changed = true

	# Check if all cells are resolved
	for x in range(dx):
		for y in range(dy):
			for z in range(dz):
				if grid_state[Vector3i(x, y, z)] == 0:
					return false # Still has unknowns

	# Verify that the resolved state matches the target shape
	for x in range(dx):
		for y in range(dy):
			for z in range(dz):
				var v = Vector3i(x, y, z)
				var is_target = target_set.has(v)
				var resolved_state = grid_state[v]
				if is_target and resolved_state != 2:
					return false
				if not is_target and resolved_state != 1:
					return false

	return true

static func _get_line_clue(hints: Dictionary, axis: int, a1: int, a2: int) -> Array:
	var axis_key = ["x", "y", "z"][axis]
	if not hints.has(axis_key):
		return []

	var key = str(a1) + "," + str(a2)
	if hints[axis_key].has(key):
		return hints[axis_key][key]
	return []

static func _get_valid_configurations(clue: Array, current_state: Array) -> Array:
	var valid_configs = []
	_solve_line(clue, current_state, 0, 0, [], valid_configs)
	return valid_configs

static func _solve_line(clue: Array, current_state: Array, current_idx: int, clue_idx: int, current_config: Array, valid_configs: Array) -> void:
	if current_idx == current_state.size():
		if clue_idx == clue.size():
			valid_configs.append(current_config.duplicate())
		return

	var can_be_empty = current_state[current_idx] == 0 or current_state[current_idx] == 1
	var can_be_target = current_state[current_idx] == 0 or current_state[current_idx] == 2

	# Option 1: Empty
	if can_be_empty:
		current_config.append(1)
		_solve_line(clue, current_state, current_idx + 1, clue_idx, current_config, valid_configs)
		current_config.pop_back()

	# Option 2: Target block (start of a clue)
	if clue_idx < clue.size():
		var block_size = clue[clue_idx]
		if current_idx + block_size <= current_state.size():
			var valid = true
			for i in range(block_size):
				if current_state[current_idx + i] == 1:
					valid = false
					break

			if valid:
				# Also check the trailing space (must be empty or end of line)
				var end_idx = current_idx + block_size
				if end_idx < current_state.size() and current_state[end_idx] == 2:
					valid = false

				if valid:
					for i in range(block_size):
						current_config.append(2)

					if end_idx < current_state.size():
						current_config.append(1)
						_solve_line(clue, current_state, end_idx + 1, clue_idx + 1, current_config, valid_configs)
						current_config.pop_back()
					else:
						_solve_line(clue, current_state, end_idx, clue_idx + 1, current_config, valid_configs)

					for i in range(block_size):
						current_config.pop_back()
