class_name VoxelLogicSolver
extends RefCounted

## Constraint solver for the three-dimensional nonogram clue format.
## solve_structured() only exposes a solution when exactly one complete
## assignment exists.  The legacy solve() API returns an empty map for
## ambiguous or contradictory input rather than guessing unknown targets.

enum CellState { BLANK, UNKNOWN, PAINTED }
enum HintType { SIMPLE, CIRCLE, SQUARE }
enum SolveStatus { SOLVED, AMBIGUOUS, CONTRADICTORY, INVALID }

const STATUS_SOLVED: String = "solved"
const STATUS_AMBIGUOUS: String = "ambiguous"
const STATUS_CONTRADICTORY: String = "contradictory"
const STATUS_INVALID: String = "invalid"
const MAX_SOLVER_DIMENSION: int = 5
const MAX_SOLVER_CELLS: int = 125
const MAX_GRID_SIZE: int = MAX_SOLVER_DIMENSION
const MAX_ACTIVE_CELLS: int = MAX_SOLVER_CELLS
const AXIS_KEYS: Array = ["x_axis", "y_axis", "z_axis"]

static func solve(dims: Vector3i, hints: Variant) -> Dictionary:
	var result: Dictionary = _solve_input(dims, hints)
	if str(result.get("status", STATUS_INVALID)) != STATUS_SOLVED:
		return {}
	return result.get("solution", {})

static func solve_structured(dims: Vector3i, clues: Variant) -> Dictionary:
	if clues is Dictionary:
		return _solve_prepared_input(dims, clues)
	return _solve_input(dims, clues)

static func analyze(dims: Vector3i, clues: Variant) -> Dictionary:
	return _solve_input(dims, clues)

static func solve_puzzle(dims: Vector3i, clues: Dictionary) -> Dictionary:
	return solve_structured(dims, clues)

static func solve_with_status(dims: Vector3i, hints: Variant) -> Dictionary:
	return _solve_input(dims, hints)

static func solve_detailed(dims: Vector3i, hints: Variant) -> Dictionary:
	return _solve_input(dims, hints)

static func solve_structured_any(dims: Vector3i, hints: Variant) -> Dictionary:
	return _solve_input(dims, hints)

static func _solve_input(dims: Vector3i, input_value: Variant) -> Dictionary:
	if input_value is Dictionary:
		return _solve_prepared_input(dims, input_value)
	if input_value is Array:
		var prepared: Dictionary = _legacy_nested_to_clues(dims, input_value)
		if not bool(prepared.get("ok", false)):
			return _error_result(STATUS_INVALID, prepared.get("errors", []))
		return solve_structured(dims, prepared.get("clues", {}))
	return _error_result(STATUS_INVALID, ["hints must be a dictionary or nested array"])

static func _solve_prepared_input(dims: Vector3i, input_value: Dictionary) -> Dictionary:
	var dimensions_result: Dictionary = _validate_dimensions(dims)
	if not bool(dimensions_result.get("ok", false)):
		return _error_result(STATUS_INVALID, dimensions_result.get("errors", []))
	var clue_result: Dictionary = _prepare_clues(dims, input_value)
	if not bool(clue_result.get("ok", false)):
		var status: String = STATUS_CONTRADICTORY if bool(clue_result.get("contradictory", false)) else STATUS_INVALID
		return _error_result(status, clue_result.get("errors", []))
	var lines: Array = _build_lines(dims, clue_result.get("clues", {}))
	var states: Dictionary = _new_states(dims)
	var propagation: Dictionary = _propagate(states, lines)
	if not bool(propagation.get("ok", false)):
		return _error_result(STATUS_CONTRADICTORY, propagation.get("errors", []))
	var unknown_count: int = _count_unknown(states)
	if unknown_count == 0:
		return _success_result(_states_to_solution(states), states, 1)
	var search_result: Dictionary = _find_solutions(states, lines, 2)
	var solutions: Array = search_result.get("solutions", [])
	if not bool(search_result.get("complete", true)):
		var incomplete_result: Dictionary = _base_result(STATUS_AMBIGUOUS)
		incomplete_result["solution_count"] = solutions.size()
		incomplete_result["unknown_count"] = unknown_count
		incomplete_result["states"] = states.duplicate(true)
		incomplete_result["search_complete"] = false
		return incomplete_result
	if solutions.is_empty():
		return _error_result(STATUS_CONTRADICTORY, search_result.get("errors", []))
	if solutions.size() >= 2:
		var ambiguous_result: Dictionary = _base_result(STATUS_AMBIGUOUS)
		ambiguous_result["solution_count"] = 2
		ambiguous_result["unknown_count"] = unknown_count
		ambiguous_result["states"] = states.duplicate(true)
		ambiguous_result["search_complete"] = bool(search_result.get("complete", false))
		return ambiguous_result
	var unique_result: Dictionary = _success_result(solutions[0], states, 1)
	unique_result["states"] = states.duplicate(true)
	unique_result["unknown_count"] = 0
	return unique_result

static func _error_result(status: String, errors: Variant) -> Dictionary:
	var result: Dictionary = _base_result(status)
	result["errors"] = errors.duplicate() if errors is Array else [str(errors)]
	return result

static func _base_result(status: String) -> Dictionary:
	return {
		"status": status,
		"is_solved": status == STATUS_SOLVED,
		"is_ambiguous": status == STATUS_AMBIGUOUS,
		"is_contradictory": status == STATUS_CONTRADICTORY,
		"is_valid": status != STATUS_INVALID,
		"valid": status != STATUS_INVALID,
		"solved": status == STATUS_SOLVED,
		"ambiguous": status == STATUS_AMBIGUOUS,
		"contradictory": status == STATUS_CONTRADICTORY,
		"solution": {},
		"states": {},
		"solution_count": 0,
		"unknown_count": 0,
		"errors": [],
		"search_complete": true,
	}

static func _success_result(solution: Dictionary, states: Dictionary, solution_count: int) -> Dictionary:
	var result: Dictionary = _base_result(STATUS_SOLVED)
	result["solution"] = solution.duplicate(true)
	result["states"] = states.duplicate(true)
	result["solution_count"] = solution_count
	return result

static func _validate_dimensions(dims: Vector3i) -> Dictionary:
	var errors: Array = []
	if dims.x <= 0 or dims.y <= 0 or dims.z <= 0:
		errors.append("dimensions must be positive")
	if dims.x > MAX_SOLVER_DIMENSION or dims.y > MAX_SOLVER_DIMENSION or dims.z > MAX_SOLVER_DIMENSION:
		errors.append("dimensions exceed solver cap")
	var cell_count: int = dims.x * dims.y * dims.z
	if cell_count > MAX_SOLVER_CELLS:
		errors.append("grid exceeds solver cell cap")
	return {"ok": errors.is_empty(), "errors": errors}

static func _prepare_clues(dims: Vector3i, input_value: Dictionary) -> Dictionary:
	var result: Dictionary = {"ok": false, "contradictory": false, "clues": {}, "errors": []}
	var errors: Array = []
	var clues: Dictionary = {}
	var found_axis: bool = false
	var strict_modern_nulls: bool = input_value.has("x_axis") or input_value.has("y_axis") or input_value.has("z_axis")
	for raw_axis: Variant in input_value.keys():
		var axis_name: String = _canonical_axis_name(str(raw_axis))
		if axis_name == "":
			errors.append("unknown clue axis '%s'" % str(raw_axis))
			continue
		found_axis = true
		if clues.has(axis_name):
			errors.append("duplicate clue axis '%s'" % axis_name)
			continue
		var axis_value: Variant = input_value[raw_axis]
		if not axis_value is Dictionary:
			errors.append("clue axis '%s' must be a dictionary" % axis_name)
			continue
		var axis_result: Dictionary = _prepare_axis(dims, axis_name, axis_value, strict_modern_nulls)
		_append_errors(errors, axis_result.get("errors", []))
		if bool(axis_result.get("contradictory", false)):
			result["contradictory"] = true
		clues[axis_name] = axis_result.get("clues", {})
	if not found_axis and not errors.is_empty():
		result["errors"] = errors
		return result
	result["clues"] = clues
	result["errors"] = errors
	result["ok"] = errors.is_empty()
	return result

static func _prepare_axis(dims: Vector3i, axis_name: String, axis_value: Dictionary, strict_modern_nulls: bool = false) -> Dictionary:
	var result: Dictionary = {"ok": false, "contradictory": false, "clues": {}, "errors": []}
	var errors: Array = []
	var clues: Dictionary = {}
	var axis_index: int = AXIS_KEYS.find(axis_name)
	var first_size: int = [dims.y, dims.x, dims.x][axis_index]
	var second_size: int = [dims.z, dims.z, dims.y][axis_index]
	var line_length: int = [dims.x, dims.y, dims.z][axis_index]
	if axis_value.size() > first_size * second_size:
		errors.append("clue axis '%s' has too many lines" % axis_name)
		result["errors"] = errors
		return result
	for raw_key: Variant in axis_value.keys():
		if not raw_key is String:
			errors.append("clue line keys must be strings")
			continue
		var parts: PackedStringArray = str(raw_key).split(",", false)
		var first_value: Variant = _parse_integer_text(parts[0]) if parts.size() == 2 else null
		var second_value: Variant = _parse_integer_text(parts[1]) if parts.size() == 2 else null
		if first_value == null or second_value == null:
			errors.append("invalid clue line key '%s'" % str(raw_key))
			continue
		var first: int = int(first_value)
		var second: int = int(second_value)
		if first < 0 or first >= first_size or second < 0 or second >= second_size:
			errors.append("clue line '%s' is outside the grid" % str(raw_key))
			continue
		var line_key: String = "%d,%d" % [first, second]
		if clues.has(line_key):
			errors.append("duplicate clue line '%s'" % line_key)
			continue
		var line_value: Variant = axis_value[raw_key]
		if line_value == null:
			if strict_modern_nulls:
				errors.append("modern clue line '%s' cannot be null" % str(raw_key))
			continue
		var line_result: Dictionary = _prepare_line(line_value, line_length)
		_append_errors(errors, line_result.get("errors", []))
		if bool(line_result.get("contradictory", false)):
			result["contradictory"] = true
		if bool(line_result.get("ok", false)):
			clues["%d,%d" % [first, second]] = line_result["clue"]
	result["clues"] = clues
	result["errors"] = errors
	result["ok"] = errors.is_empty()
	return result

static func _prepare_line(value: Variant, line_length: int) -> Dictionary:
	var result: Dictionary = {"ok": false, "contradictory": false, "clue": {}, "errors": []}
	if value is Array:
		var array_value: Array = value
		if array_value.is_empty():
			result["ok"] = true
			result["clue"] = _exact_clue([])
			return result
		if _all_numeric(array_value):
			return _prepare_exact_blocks(array_value, line_length)
		if array_value.size() == 1:
			return _prepare_line(array_value[0], line_length)
		result["errors"].append("a line may contain only one legacy hint object")
		return result
	if value is Dictionary:
		var dictionary_value: Dictionary = value
		if dictionary_value.has("blocks") or dictionary_value.has("total"):
			return _prepare_modern_dictionary(dictionary_value, line_length)
		if dictionary_value.has("num"):
			return _prepare_legacy_dictionary(dictionary_value, line_length)
		result["errors"].append("clue object has no supported fields")
		return result
	if _is_integer_value(value):
		return _prepare_exact_blocks([int(value)], line_length)
	result["errors"].append("unsupported clue value")
	return result

static func _prepare_modern_dictionary(value: Dictionary, line_length: int) -> Dictionary:
	var result: Dictionary = {"ok": false, "contradictory": false, "clue": {}, "errors": []}
	if not value.has("total") or not value.has("blocks"):
		result["errors"].append("modern clue requires total and blocks")
		return result
	if value.has("block_lengths_known") and not bool(value["block_lengths_known"]):
		if not _is_integer_value(value["total"]) or int(value["total"]) < 0:
			result["errors"].append("clue total is invalid")
			return result
		var group_count_value: Variant = value.get("group_count", 0)
		var min_group_count_value: Variant = value.get("min_group_count", 0)
		if not _is_integer_value(group_count_value) or not _is_integer_value(min_group_count_value) or int(group_count_value) < 0 or int(min_group_count_value) < 0:
			result["errors"].append("legacy grouped clue fields are invalid")
			return result
		var soft_clue: Dictionary = {"total": int(value["total"]), "blocks": [], "block_lengths_known": false, "group_count": int(group_count_value), "min_group_count": int(min_group_count_value)}
		if not _clue_fits(soft_clue, line_length):
			result["errors"].append("legacy grouped clue cannot fit on its line")
			return result
		result["ok"] = true
		result["clue"] = soft_clue
		return result
	if not _is_integer_value(value["total"]) or int(value["total"]) < 0:
		result["errors"].append("clue total is invalid")
		return result
	var blocks: Array = []
	if value["blocks"] is Array:
		blocks = value["blocks"]
	elif value["blocks"] is PackedInt32Array:
		blocks = Array(value["blocks"])
	else:
		result["errors"].append("clue blocks is not an array")
		return result
	var normalized: Array = []
	for block: Variant in blocks:
		if not _is_integer_value(block) or int(block) <= 0:
			result["errors"].append("clue block length is invalid")
			return result
		normalized.append(int(block))
	var total: int = int(value["total"])
	if _sum_ints(normalized) != total:
		result["contradictory"] = true
		result["errors"].append("clue total does not equal block sum")
		return result
	var clue: Dictionary = _exact_clue(normalized)
	if not _clue_fits(clue, line_length):
		result["contradictory"] = true
		result["errors"].append("clue cannot fit on its line")
		return result
	result["ok"] = true
	result["clue"] = clue
	return result

static func _prepare_legacy_dictionary(value: Dictionary, line_length: int) -> Dictionary:
	var result: Dictionary = {"ok": false, "contradictory": false, "clue": {}, "errors": []}
	if not _is_integer_value(value.get("num")) or int(value["num"]) < 0:
		result["errors"].append("legacy hint num is invalid")
		return result
	if int(value["num"]) > line_length:
		result["contradictory"] = true
		result["errors"].append("legacy hint num cannot fit on its line")
		return result
	var number: int = int(value["num"])
	var hint_type: int = 0
	if value.has("type"):
		if not _is_integer_value(value["type"]):
			result["errors"].append("legacy hint type is invalid")
			return result
		hint_type = int(value["type"])
	if hint_type < 0 or hint_type > 2:
		result["errors"].append("legacy hint type is invalid")
		return result
	if hint_type == HintType.SIMPLE:
		var blocks: Array = []
		if number > 0:
			blocks.append(number)
		var clue: Dictionary = _exact_clue(blocks)
		if not _clue_fits(clue, line_length):
			result["contradictory"] = true
			result["errors"].append("legacy simple hint cannot fit")
			return result
		result["ok"] = true
		result["clue"] = clue
		return result
	var clue: Dictionary = {"total": number, "blocks": [], "block_lengths_known": false, "group_count": 2 if hint_type == HintType.CIRCLE else 0, "min_group_count": 0 if hint_type == HintType.CIRCLE else 3}
	if not _clue_fits(clue, line_length):
		result["contradictory"] = true
		result["errors"].append("legacy grouped hint cannot fit")
		return result
	result["ok"] = true
	result["clue"] = clue
	return result

static func _prepare_exact_blocks(blocks: Array, line_length: int) -> Dictionary:
	var result: Dictionary = {"ok": false, "contradictory": false, "clue": {}, "errors": []}
	var normalized: Array = []
	for block: Variant in blocks:
		if not _is_integer_value(block) or int(block) <= 0:
			result["errors"].append("block length is invalid")
			return result
		normalized.append(int(block))
	var clue: Dictionary = _exact_clue(normalized)
	if not _clue_fits(clue, line_length):
		result["contradictory"] = true
		result["errors"].append("clue cannot fit on its line")
		return result
	result["ok"] = true
	result["clue"] = clue
	return result

static func _legacy_nested_to_clues(dims: Vector3i, value: Array) -> Dictionary:
	var result: Dictionary = {"ok": false, "clues": {}, "errors": []}
	var errors: Array = []
	if value.size() != 3:
		errors.append("legacy hints must have three axes")
		result["errors"] = errors
		return result
	var clues: Dictionary = {}
	for axis_index: int in range(3):
		var axis_value: Variant = value[axis_index]
		var axis_name: String = AXIS_KEYS[axis_index]
		if not axis_value is Array:
			errors.append("legacy axis is not an array")
			continue
		var axis_array: Array = axis_value
		var first_size: int = [dims.y, dims.x, dims.x][axis_index]
		var second_size: int = [dims.z, dims.z, dims.y][axis_index]
		var line_length: int = [dims.x, dims.y, dims.z][axis_index]
		if axis_array.size() > first_size:
			errors.append("legacy axis has too many rows")
		var axis_clues: Dictionary = {}
		for first: int in range(mini(axis_array.size(), first_size)):
			var row_value: Variant = axis_array[first]
			if row_value == null:
				continue
			if not row_value is Array:
				errors.append("legacy hint row is not an array")
				continue
			var row: Array = row_value
			if row.size() > second_size:
				errors.append("legacy hint row has too many entries")
			for second: int in range(mini(row.size(), second_size)):
				var line_value: Variant = row[second]
				if line_value == null or (line_value is Array and line_value.is_empty()):
					continue
				var line_result: Dictionary = _prepare_line(line_value, line_length)
				_append_errors(errors, line_result.get("errors", []))
				if bool(line_result.get("ok", false)):
					axis_clues["%d,%d" % [first, second]] = line_result["clue"]
		clues[axis_name] = axis_clues
	result["clues"] = clues
	result["errors"] = errors
	result["ok"] = errors.is_empty()
	return result

static func _build_lines(dims: Vector3i, clues: Dictionary) -> Array:
	var lines: Array = []
	for axis_index: int in range(3):
		var axis_name: String = AXIS_KEYS[axis_index]
		var first_size: int = [dims.y, dims.x, dims.x][axis_index]
		var second_size: int = [dims.z, dims.z, dims.y][axis_index]
		var line_length: int = [dims.x, dims.y, dims.z][axis_index]
		var axis_clues: Dictionary = clues.get(axis_name, {})
		for first: int in range(first_size):
			for second: int in range(second_size):
				var coordinates: Array = []
				for line_index: int in range(line_length):
					coordinates.append(_line_coordinate(axis_index, first, second, line_index))
				var key: String = "%d,%d" % [first, second]
				lines.append({"axis": axis_index, "key": key, "length": line_length, "coordinates": coordinates, "constrained": axis_clues.has(key), "clue": axis_clues.get(key, {})})
	return lines

static func _new_states(dims: Vector3i) -> Dictionary:
	var states: Dictionary = {}
	for x: int in range(dims.x):
		for y: int in range(dims.y):
			for z: int in range(dims.z):
				states[Vector3i(x, y, z)] = CellState.UNKNOWN
	return states

static func _propagate(states: Dictionary, lines: Array) -> Dictionary:
	var changed: bool = true
	var iterations: int = 0
	var maximum_iterations: int = maxi(1, states.size() * 3 + lines.size() + 1)
	while changed and iterations < maximum_iterations:
		changed = false
		iterations += 1
		for line: Dictionary in lines:
			if not bool(line.get("constrained", false)):
				continue
			var candidates: Array = _valid_configurations(line, states)
			if candidates.is_empty():
				return {"ok": false, "errors": ["line %s contradicts known cells" % str(line.get("key", ""))]}
			for index: int in range(int(line["length"])):
				var coordinate: Vector3i = line["coordinates"][index]
				var first_value: int = candidates[0][index]
				var same: bool = true
				for candidate_index: int in range(1, candidates.size()):
					if candidates[candidate_index][index] != first_value:
						same = false
						break
				if not same:
					continue
				var desired: int = CellState.PAINTED if first_value == 1 else CellState.BLANK
				var state_value: int = int(states[coordinate])
				if state_value == CellState.UNKNOWN:
					states[coordinate] = desired
					changed = true
				elif state_value != desired:
					return {"ok": false, "errors": ["line %s contradicts an already-known cell" % str(line.get("key", ""))]}
	return {"ok": true, "errors": []}

static func _find_solutions(initial_states: Dictionary, lines: Array, solution_limit: int) -> Dictionary:
	var solutions: Array = []
	var context: Dictionary = {"nodes": 0}
	var search_result: Dictionary = _search_recursive_inner(initial_states, lines, solution_limit, solutions, context)
	return {"solutions": solutions, "complete": bool(search_result.get("complete", true)), "errors": []}

static func _search_recursive_inner(states: Dictionary, lines: Array, solution_limit: int, solutions: Array, context: Dictionary) -> Dictionary:
	if solutions.size() >= solution_limit:
		return {"complete": true}
	context["nodes"] = int(context.get("nodes", 0)) + 1
	if int(context["nodes"]) > 1000000:
		return {"complete": false}
	var unknown: Vector3i = _choose_unknown(states, lines)
	if unknown.x < 0:
		solutions.append(_states_to_solution(states))
		return {"complete": true}
	for value: int in [CellState.PAINTED, CellState.BLANK]:
		var branch: Dictionary = states.duplicate(true)
		branch[unknown] = value
		var propagation: Dictionary = _propagate(branch, lines)
		if not bool(propagation.get("ok", false)):
			continue
		var recursive_result: Dictionary = _search_recursive_inner(branch, lines, solution_limit, solutions, context)
		if not bool(recursive_result.get("complete", true)):
			return recursive_result
		if solutions.size() >= solution_limit:
			break
	return {"complete": true}

static func _choose_unknown(states: Dictionary, lines: Array) -> Vector3i:
	var best: Vector3i = Vector3i(-1, -1, -1)
	var best_score: int = -1
	for line: Dictionary in lines:
		if not bool(line.get("constrained", false)):
			continue
		if _valid_configurations(line, states).is_empty():
			continue
		for index: int in range(int(line["length"])):
			var coordinate: Vector3i = line["coordinates"][index]
			if int(states[coordinate]) != CellState.UNKNOWN:
				continue
			var score: int = 1
			for other: Dictionary in lines:
				if bool(other.get("constrained", false)) and other["coordinates"].has(coordinate):
					score += 1
			if score > best_score:
				best_score = score
				best = coordinate
	if best.x >= 0:
		return best
	for coordinate: Vector3i in states.keys():
		if int(states[coordinate]) == CellState.UNKNOWN:
			return coordinate
	return Vector3i(-1, -1, -1)

static func _valid_configurations(line: Dictionary, states: Dictionary) -> Array:
	var length: int = int(line.get("length", 0))
	if length <= 0 or length > 20:
		return []
	var candidates: Array = []
	for mask: int in range(1 << length):
		var candidate: Array = []
		var matches: bool = true
		for index: int in range(length):
			var value: int = 1 if (mask & (1 << index)) != 0 else 0
			var coordinate: Vector3i = line["coordinates"][index]
			var known: int = int(states[coordinate])
			if (known == CellState.PAINTED and value == 0) or (known == CellState.BLANK and value == 1):
				matches = false
				break
			candidate.append(value)
		if matches and _matches_clue(candidate, line.get("clue", {})):
			candidates.append(candidate)
	return candidates

static func _matches_clue(configuration: Array, clue: Dictionary) -> bool:
	if clue.is_empty():
		return true
	var total: int = 0
	for value: int in configuration:
		total += value
	if clue.has("total") and total != int(clue["total"]):
		return false
	var groups: Array = _groups_in_configuration(configuration)
	if bool(clue.get("block_lengths_known", true)):
		var expected: Array = clue.get("blocks", [])
		if groups.size() != expected.size():
			return false
		for index: int in range(expected.size()):
			if groups[index] != int(expected[index]):
				return false
		return true
	if clue.has("group_count"):
		return groups.size() == int(clue["group_count"])
	if clue.has("min_group_count"):
		return groups.size() >= int(clue["min_group_count"])
	return true

static func _groups_in_configuration(configuration: Array) -> Array:
	var groups: Array = []
	var current: int = 0
	for value: int in configuration:
		if value == 1:
			current += 1
		elif current > 0:
			groups.append(current)
			current = 0
	if current > 0:
		groups.append(current)
	return groups

static func _clue_fits(clue: Dictionary, line_length: int) -> bool:
	if line_length <= 0:
		return false
	var total: int = int(clue.get("total", -1))
	if total < 0 or total > line_length:
		return false
	if bool(clue.get("block_lengths_known", true)):
		var blocks: Array = clue.get("blocks", [])
		if _sum_ints(blocks) != total:
			return false
		var required: int = total
		if not blocks.is_empty():
			required += blocks.size() - 1
		return required <= line_length
	var group_count: int = int(clue.get("group_count", 0))
	var min_group_count: int = int(clue.get("min_group_count", 0))
	var required_groups: int = group_count if group_count > 0 else min_group_count
	if required_groups <= 0 or total < required_groups or total + required_groups - 1 > line_length:
		return false
	return true

static func _exact_clue(blocks: Array) -> Dictionary:
	var copied: Array = []
	for block: Variant in blocks:
		copied.append(int(block))
	return {"total": _sum_ints(copied), "blocks": copied, "block_lengths_known": true}

static func _states_to_solution(states: Dictionary) -> Dictionary:
	var solution: Dictionary = {}
	for coordinate: Vector3i in states.keys():
		solution[coordinate] = int(states[coordinate]) == CellState.PAINTED
	return solution

static func _count_unknown(states: Dictionary) -> int:
	var count: int = 0
	for state: Variant in states.values():
		if int(state) == CellState.UNKNOWN:
			count += 1
	return count

static func _line_coordinate(axis_index: int, first: int, second: int, line_index: int) -> Vector3i:
	if axis_index == 0:
		return Vector3i(line_index, first, second)
	if axis_index == 1:
		return Vector3i(first, line_index, second)
	return Vector3i(first, second, line_index)

static func _canonical_axis_name(value: String) -> String:
	var normalized: String = value.to_lower()
	if normalized == "x_axis" or normalized == "x":
		return "x_axis"
	if normalized == "y_axis" or normalized == "y":
		return "y_axis"
	if normalized == "z_axis" or normalized == "z":
		return "z_axis"
	return ""

static func _parse_integer_text(value: String) -> Variant:
	if not value.is_valid_int():
		return null
	return value.to_int()


static func _is_integer_value(value: Variant) -> bool:
	var value_type: int = typeof(value)
	if value_type == TYPE_INT:
		return true
	if value_type != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and floor(number) == number

static func _all_numeric(values: Array) -> bool:
	for value: Variant in values:
		if not _is_integer_value(value):
			return false
	return true

static func _sum_ints(values: Array) -> int:
	var total: int = 0
	for value: Variant in values:
		if _is_integer_value(value):
			total += int(value)
	return total

static func _append_errors(target: Array, values: Variant) -> void:
	if not values is Array:
		return
	for value: Variant in values:
		target.append(str(value))

## Compatibility helper retained for older tests/content.
static func _solve_line(current_line: Array, num: int, type: int) -> Array:
	var length: int = current_line.size()
	var states: Dictionary = {}
	var coordinates: Array = []
	for index: int in range(length):
		states[index] = int(current_line[index])
		coordinates.append(index)
	var clue: Dictionary = {"total": num, "blocks": [num] if type == HintType.SIMPLE and num > 0 else [], "block_lengths_known": type == HintType.SIMPLE}
	if type == HintType.CIRCLE:
		clue["group_count"] = 2
	elif type == HintType.SQUARE:
		clue["min_group_count"] = 3
	if not _clue_fits(clue, length):
		return []
	var candidates: Array = _valid_configurations({"length": length, "coordinates": coordinates, "clue": clue}, states)
	if candidates.is_empty():
		return []
	var result: Array = []
	for index: int in range(length):
		var all_painted: bool = true
		var all_blank: bool = true
		for candidate: Array in candidates:
			if candidate[index] == 1:
				all_blank = false
			else:
				all_painted = false
		result.append(CellState.PAINTED if all_painted else (CellState.BLANK if all_blank else CellState.UNKNOWN))
	return result
