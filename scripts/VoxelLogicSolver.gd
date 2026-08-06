class_name VoxelLogicSolver

enum CellState { BLANK, UNKNOWN, PAINTED }
enum HintType { SIMPLE, CIRCLE, SQUARE }

# Solve a puzzle defined by dims and hints, returning a dictionary of Vector3i -> bool (true if painted, false if blank)
static func solve(dims: Vector3i, hints: Array) -> Dictionary:
	var grid = {}
	# Initialize all cells to UNKNOWN
	for x in range(dims.x):
		for y in range(dims.y):
			for z in range(dims.z):
				grid[Vector3i(x, y, z)] = CellState.UNKNOWN

	var changed = true
	var iterations = 0
	while changed and iterations < 100:
		changed = false
		iterations += 1

		# Solve X lines (fixed y, z)
		for y in range(dims.y):
			for z in range(dims.z):
				if y < hints[0].size() and z < hints[0][y].size() and hints[0][y][z] != null:
					var line_hints = hints[0][y][z]
					if line_hints is Array and line_hints.size() > 0 and line_hints[0] != null:
						var hint = line_hints[0]
						var current_line = []
						for x in range(dims.x):
							current_line.append(grid[Vector3i(x, y, z)])
						var solved = _solve_line(current_line, int(hint["num"]), int(hint["type"]))
						if solved.size() > 0:
							for x in range(dims.x):
								if grid[Vector3i(x, y, z)] != solved[x]:
									grid[Vector3i(x, y, z)] = solved[x]
									changed = true

		# Solve Y lines (fixed x, z)
		for x in range(dims.x):
			for z in range(dims.z):
				if x < hints[1].size() and z < hints[1][x].size() and hints[1][x][z] != null:
					var line_hints = hints[1][x][z]
					if line_hints is Array and line_hints.size() > 0 and line_hints[0] != null:
						var hint = line_hints[0]
						var current_line = []
						for y in range(dims.y):
							current_line.append(grid[Vector3i(x, y, z)])
						var solved = _solve_line(current_line, int(hint["num"]), int(hint["type"]))
						if solved.size() > 0:
							for y in range(dims.y):
								if grid[Vector3i(x, y, z)] != solved[y]:
									grid[Vector3i(x, y, z)] = solved[y]
									changed = true

		# Solve Z lines (fixed x, y)
		for x in range(dims.x):
			for y in range(dims.y):
				if x < hints[2].size() and y < hints[2][x].size() and hints[2][x][y] != null:
					var line_hints = hints[2][x][y]
					if line_hints is Array and line_hints.size() > 0 and line_hints[0] != null:
						var hint = line_hints[0]
						var current_line = []
						for z in range(dims.z):
							current_line.append(grid[Vector3i(x, y, z)])
						var solved = _solve_line(current_line, int(hint["num"]), int(hint["type"]))
						if solved.size() > 0:
							for z in range(dims.z):
								if grid[Vector3i(x, y, z)] != solved[z]:
									grid[Vector3i(x, y, z)] = solved[z]
									changed = true

	# Treat PAINTED and candidate UNKNOWN cells as targets
	var solution = {}
	for pos in grid.keys():
		solution[pos] = (grid[pos] != CellState.BLANK)
	return solution

# Solve a single line using configuration filtering
static func _solve_line(current_line: Array, num: int, type: int) -> Array:
	var length = current_line.size()
	var valid_configs = []

	var total_configs = 1 << length
	for i in range(total_configs):
		var config = []
		var painted_count = 0
		for j in range(length):
			if (i & (1 << j)) != 0:
				config.append(CellState.PAINTED)
				painted_count += 1
			else:
				config.append(CellState.BLANK)
		
		# 1. Must match current line state
		var match_current = true
		for j in range(length):
			if current_line[j] == CellState.PAINTED and config[j] != CellState.PAINTED:
				match_current = false
				break
			if current_line[j] == CellState.BLANK and config[j] != CellState.BLANK:
				match_current = false
				break
		if not match_current:
			continue

		# 2. Must match the hint num
		if painted_count != num:
			continue

		# 3. Must match the hint type (groups count)
		var groups = []
		var in_group = false
		var current_group_len = 0
		for j in range(length):
			if config[j] == CellState.PAINTED:
				if not in_group:
					in_group = true
					current_group_len = 1
				else:
					current_group_len += 1
			else:
				if in_group:
					groups.append(current_group_len)
					in_group = false
		if in_group:
			groups.append(current_group_len)

		var valid_type = false
		if type == HintType.SIMPLE:
			valid_type = (groups.size() == 1 or (num == 0 and groups.size() == 0))
		elif type == HintType.CIRCLE:
			valid_type = (groups.size() == 2)
		elif type == HintType.SQUARE:
			valid_type = (groups.size() >= 3)

		if valid_type:
			valid_configs.append(config)

	if valid_configs.is_empty():
		return []

	var result = []
	for j in range(length):
		var all_painted = true
		var all_blank = true
		for config in valid_configs:
			if config[j] == CellState.PAINTED:
				all_blank = false
			else:
				all_painted = false
		if all_painted:
			result.append(CellState.PAINTED)
		elif all_blank:
			result.append(CellState.BLANK)
		else:
			result.append(CellState.UNKNOWN)
	return result
