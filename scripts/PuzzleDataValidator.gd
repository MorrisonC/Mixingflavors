extends RefCounted
class_name PuzzleDataValidator

## Central boundary for puzzle-data validation and normalization.
##
## The project has accumulated several generations of puzzle JSON.  This class
## deliberately keeps the accepted input formats at this boundary and emits a
## single, target-authoritative representation:
##
##     dims/grid_size: [int, int, int]
##     target_voxels: [[x, y, z], ...]
##     clues: { x_axis: { "y,z": { total, blocks } }, ... }
##
## A target is never manufactured from a partial line deduction.  Hints-only
## data is promoted to a target only after VoxelLogicSolver reports exactly one
## solution.

const VoxelLogicSolverClass = preload("res://scripts/VoxelLogicSolver.gd")
const MAX_DIMENSION: int = 5
const MAX_CELLS: int = 125
const MAX_GRID_SIZE: int = MAX_DIMENSION
const MAX_ACTIVE_CELLS: int = MAX_CELLS

const STATUS_SOLVED: String = "solved"
const STATUS_AMBIGUOUS: String = "ambiguous"
const STATUS_CONTRADICTORY: String = "contradictory"
const STATUS_INVALID: String = "invalid"

enum ValidationStatus {
	SOLVED,
	AMBIGUOUS,
	CONTRADICTORY,
	INVALID,
}

const AXIS_KEYS: Array = ["x_axis", "y_axis", "z_axis"]
const LEGACY_AXIS_KEYS: Array = ["x", "y", "z"]
const _DROPPED_KEYS: Array = [
	"dims",
	"grid_size",
	"target_voxels",
	"cells",
	"hints",
	"clues",
	"voxel_count",
	"solvable",
]


## Analyze and normalize a puzzle.  The returned dictionary is a structured
## validation result; for convenience its canonical fields (dims, clues, and
## target_voxels) are also copied to the top level when a canonical puzzle is
## available.
static func analyze_puzzle(puzzle_data: Dictionary, require_unique: bool = true, repair_target_clues: bool = true) -> Dictionary:
	var result: Dictionary = _new_result()
	result["source_schema"] = _describe_source(puzzle_data)

	var dimensions_result: Dictionary = _parse_dimensions(puzzle_data)
	_append_errors(result, dimensions_result.get("errors", []))
	if not bool(dimensions_result.get("ok", false)):
		_set_invalid(result)
		return result

	var dims: Vector3i = dimensions_result["dims"]
	result["dims_vector"] = dims

	var target_result: Dictionary = _extract_target(puzzle_data, dims)
	_append_errors(result, target_result.get("errors", []))
	if not bool(target_result.get("ok", false)):
		_set_invalid(result)
		return result

	var target_authoritative: bool = bool(target_result.get("authoritative", false))
	var target_voxels: Array = target_result.get("voxels", [])
	result["target_authoritative_input"] = target_authoritative
	result["has_explicit_target"] = bool(puzzle_data.has("target_voxels"))
	result["has_flat_cells"] = bool(puzzle_data.has("cells"))

	var clue_result: Dictionary = _extract_clues(puzzle_data, dims)
	var clue_errors: Array = clue_result.get("errors", [])
	var clues_present: bool = bool(clue_result.get("present", false))
	var stored_clues: Dictionary = clue_result.get("clues", {})
	result["has_stored_clues"] = clues_present
	result["explicit_clue_count"] = clue_result.get("explicit_clue_count", 0)

	if not target_authoritative:
		_append_errors(result, clue_errors)
		if not clues_present:
			_append_error(result, "puzzle has no target, cells, or clues")
			_set_invalid(result)
			return result
		if not clue_errors.is_empty():
			if bool(clue_result.get("contradictory", false)):
				result["status"] = STATUS_CONTRADICTORY
				_set_status_flags(result)
			else:
				_set_invalid(result)
			return result
	else:
		if not repair_target_clues and (not clues_present or not clue_errors.is_empty()):
			# The strict legacy boolean API validates the data as supplied; it
			# does not silently turn a broken stored puzzle into a different
			# one.  Registry/normalizer callers use repair_target_clues=true.
			_append_errors(result, clue_errors)
			if not clues_present:
				_append_error(result, "target-authoritative strict validation requires stored clues")
			if bool(clue_result.get("contradictory", false)):
				result["status"] = STATUS_CONTRADICTORY
				_set_status_flags(result)
			else:
				_set_invalid(result)
			return result
		# A target is authoritative.  Bad stored clues are data-repair work,
		# not a reason to retain a contradictory puzzle.
		if repair_target_clues:
			for repair: String in _string_array(clue_errors):
				_append_repair(result, repair)
			if target_result.get("source_conflict", false):
				_append_repair(result, "flat cells disagreed with target_voxels; target_voxels won")
			if puzzle_data.has("voxel_count"):
				var stored_count: Variant = puzzle_data["voxel_count"]
				if not _is_integer_value(stored_count) or int(stored_count) != target_voxels.size():
					_append_repair(result, "voxel_count did not match stored target_voxels")
			if puzzle_data.has("solvable") and not bool(puzzle_data["solvable"]):
				_append_repair(result, "stored solvable flag was false; canonical target is authoritative")

	if target_authoritative:
		var derived_clues: Dictionary = derive_clues(dims, target_voxels)
		if repair_target_clues:
			if clues_present and (not clue_errors.is_empty() or not _clues_match(stored_clues, derived_clues)):
				_append_repair(result, "stored clues were malformed or disagreed with target; derived canonical clues")
			elif not clues_present:
				_append_repair(result, "stored clues were missing; derived canonical clues from target")

		var canonical_puzzle: Dictionary = _build_canonical_puzzle(
			puzzle_data,
			dims,
			target_voxels,
			derived_clues
		)
		_attach_canonical(result, canonical_puzzle)

		# A supplied target is already authoritative.  In repair mode the
		# canonical projection is derived from that target, so a full backtracking
		# solve would only re-discover the same answer.  Strict validation (used
		# by is_puzzle_solvable) still runs the solver against the stored clues.
		var solver_result: Dictionary
		if repair_target_clues:
			solver_result = _target_authoritative_solver_result(dims, target_voxels)
		else:
			solver_result = VoxelLogicSolverClass.solve_structured(dims, stored_clues)
		result["solver_result"] = solver_result
		result["solution"] = solver_result.get("solution", {})
		result["states"] = solver_result.get("states", {})
		result["solution_count"] = solver_result.get("solution_count", 0)
		result["unknown_count"] = solver_result.get("unknown_count", 0)
		result["status"] = solver_result.get("status", STATUS_INVALID)
		_set_status_flags(result)
		if result["status"] == STATUS_SOLVED:
			var solution: Dictionary = solver_result.get("solution", {})
			if not _solution_matches_target(solution, target_voxels):
				result["status"] = STATUS_CONTRADICTORY
				_append_error(result, "derived clues solved to a different target")
				_set_status_flags(result)
		elif result["status"] == STATUS_INVALID:
			# A derived clue should be valid by construction.  Treat an
			# unexpected solver failure as invalid rather than publishing it.
			_append_error(result, "canonical derived clues could not be analyzed")
			_set_invalid(result)
			return result

		result["target_authoritative"] = true
		result["target_source"] = "target_voxels" if puzzle_data.has("target_voxels") else "cells"
		result["ok"] = bool(result["status"] == STATUS_SOLVED)
		if not require_unique and result["status"] == STATUS_AMBIGUOUS:
			# Diagnostics/repair callers may intentionally inspect an
			# authoritative target even when its clues are not unique.  The
			# default remains strict and never promotes ambiguous data.
			result["ok"] = true
		return result

	# Hints-only data is the only path that may manufacture target_voxels.
	var solver_result: Dictionary = VoxelLogicSolverClass.solve_structured(dims, stored_clues)
	result["solver_result"] = solver_result
	result["solution"] = solver_result.get("solution", {})
	result["states"] = solver_result.get("states", {})
	result["solution_count"] = solver_result.get("solution_count", 0)
	result["unknown_count"] = solver_result.get("unknown_count", 0)
	result["status"] = solver_result.get("status", STATUS_INVALID)
	_set_status_flags(result)
	if result["status"] != STATUS_SOLVED or int(result.get("solution_count", 0)) != 1:
		# In particular, do not turn the solver's unknown cells into false or
		# true target values here.  Ambiguous and contradictory inputs have no
		# canonical target-authoritative puzzle.
		result["target_authoritative"] = false
		return result

	var solved_solution: Dictionary = solver_result.get("solution", {})
	if not _solution_is_complete(dims, solved_solution):
		result["status"] = STATUS_AMBIGUOUS
		_set_status_flags(result)
		result["target_authoritative"] = false
		return result
	var solved_target: Array = _target_from_solution(solved_solution)
	var canonical_clues: Dictionary = derive_clues(dims, solved_target)
	var canonical_puzzle: Dictionary = _build_canonical_puzzle(
		puzzle_data,
		dims,
		solved_target,
		canonical_clues
	)
	_attach_canonical(result, canonical_puzzle)
	result["target_authoritative"] = true
	result["target_source"] = "unique_constraint_solution"
	result["ok"] = true
	result["status"] = STATUS_SOLVED
	_set_status_flags(result)
	if not _clues_match(stored_clues, canonical_clues):
		_append_repair(result, "legacy hints were enriched with canonical exact clues")
	return result


## Descriptive alias for callers that use the shorter name.
static func normalize(puzzle_data: Dictionary, require_unique: bool = true) -> Dictionary:
	return analyze_puzzle(puzzle_data, require_unique)


## Return only the canonical puzzle, or an empty dictionary when the strict
## validation boundary rejects it.  Use analyze_puzzle() when status/details are
## needed.
static func normalize_puzzle(puzzle_data: Dictionary, require_unique: bool = true) -> Dictionary:
	var analysis: Dictionary = analyze_puzzle(puzzle_data, require_unique)
	if bool(analysis.get("ok", false)):
		return analysis.get("puzzle", {})
	return {}


static func canonicalize_puzzle(puzzle_data: Dictionary, require_unique: bool = true) -> Dictionary:
	return normalize_puzzle(puzzle_data, require_unique)


static func normalize_canonical(puzzle_data: Dictionary, require_unique: bool = true) -> Dictionary:
	return normalize_puzzle(puzzle_data, require_unique)


static func validate_puzzle(puzzle_data: Dictionary) -> bool:
	var analysis: Dictionary = analyze_puzzle(puzzle_data, true)
	return bool(analysis.get("ok", false))


static func is_valid(puzzle_data: Dictionary) -> bool:
	return validate_puzzle(puzzle_data)


static func validate(puzzle_data: Dictionary) -> Dictionary:
	return analyze_puzzle(puzzle_data, true)


static func normalize_and_validate(puzzle_data: Dictionary, require_unique: bool = true) -> Dictionary:
	return analyze_puzzle(puzzle_data, require_unique, true)


static func validate_and_normalize(puzzle_data: Dictionary, require_unique: bool = true) -> Dictionary:
	return analyze_puzzle(puzzle_data, require_unique, true)


static func get_canonical_puzzle(puzzle_data: Dictionary, require_unique: bool = true) -> Dictionary:
	return normalize_puzzle(puzzle_data, require_unique)


## Derive the complete exact three-axis clue projection from a target.
## Coordinates may be Vector3i values or [x, y, z] arrays.
static func derive_clues(dims: Vector3i, target_voxels: Array) -> Dictionary:
	var target_set: Dictionary = {}
	for coordinate: Variant in target_voxels:
		var parsed: Vector3i = _coerce_coordinate(coordinate, Vector3i(-1, -1, -1))
		if parsed.x >= 0:
			target_set[parsed] = true
	return _derive_clues_from_set(dims, target_set)


static func max_dimension() -> int:
	return MAX_DIMENSION


static func max_cells() -> int:
	return MAX_CELLS


static func _new_result() -> Dictionary:
	return {
		"ok": false,
		"valid": false,
		"status": STATUS_INVALID,
		"is_solved": false,
		"is_ambiguous": false,
		"is_contradictory": false,
		"solved": false,
		"ambiguous": false,
		"contradictory": false,
		"is_valid": false,
		"puzzle": {},
		"canonical": {},
		"errors": [],
		"repairs": [],
		"repair_count": 0,
		"was_repaired": false,
		"repaired": false,
		"target_authoritative": false,
		"target_source": "",
		"solution": {},
		"states": {},
		"solution_count": 0,
		"unknown_count": 0,
	}


static func _set_invalid(result: Dictionary) -> void:
	result["status"] = STATUS_INVALID
	result["ok"] = false
	result["valid"] = false
	result["is_valid"] = false
	result["is_solved"] = false
	result["is_ambiguous"] = false
	result["is_contradictory"] = false
	result["solved"] = false
	result["ambiguous"] = false
	result["contradictory"] = false


static func _set_status_flags(result: Dictionary) -> void:
	var status: String = str(result.get("status", STATUS_INVALID))
	result["is_solved"] = status == STATUS_SOLVED
	result["is_ambiguous"] = status == STATUS_AMBIGUOUS
	result["is_contradictory"] = status == STATUS_CONTRADICTORY
	result["is_valid"] = status != STATUS_INVALID
	result["valid"] = status != STATUS_INVALID
	result["solved"] = result["is_solved"]
	result["ambiguous"] = result["is_ambiguous"]
	result["contradictory"] = result["is_contradictory"]
	result["ok"] = result["is_valid"] and result["is_solved"]


static func _append_error(result: Dictionary, message: String) -> void:
	var errors: Array = result["errors"]
	if not errors.has(message):
		errors.append(message)


static func _append_errors(result: Dictionary, values: Variant) -> void:
	if not values is Array:
		return
	for value: Variant in values:
		_append_error(result, str(value))


static func _append_repair(result: Dictionary, message: String) -> void:
	var repairs: Array = result["repairs"]
	if not repairs.has(message):
		repairs.append(message)
	result["repair_count"] = repairs.size()
	result["was_repaired"] = not repairs.is_empty()
	result["repaired"] = result["was_repaired"]


static func _describe_source(puzzle_data: Dictionary) -> String:
	if puzzle_data.has("clues"):
		return "clues"
	if puzzle_data.has("hints"):
		if puzzle_data["hints"] is Array:
			return "legacy_nested_hints"
		return "legacy_hints_map"
	if puzzle_data.has("target_voxels"):
		return "target_voxels"
	if puzzle_data.has("cells"):
		return "cells"
	return "unknown"


static func _parse_dimensions(puzzle_data: Dictionary) -> Dictionary:
	var result: Dictionary = {"ok": false, "dims": Vector3i.ZERO, "errors": []}
	var errors: Array = []
	var found: bool = false
	var selected: Vector3i = Vector3i.ZERO

	for key: String in ["dims", "grid_size"]:
		if not puzzle_data.has(key):
			continue
		var parsed: Dictionary = _parse_dimension_value(puzzle_data[key])
		if not bool(parsed.get("ok", false)):
			errors.append("%s is not a valid three-dimensional size" % key)
			continue
		var candidate: Vector3i = parsed["dims"]
		if found and candidate != selected:
			errors.append("dims and grid_size disagree")
		found = true
		selected = candidate

	if not found:
		errors.append("puzzle is missing dims or grid_size")
		result["errors"] = errors
		return result
	if selected.x <= 0 or selected.y <= 0 or selected.z <= 0:
		errors.append("dimensions must be positive")
	if selected.x > MAX_DIMENSION or selected.y > MAX_DIMENSION or selected.z > MAX_DIMENSION:
		errors.append("dimensions exceed the %dx%dx%d gameplay cap" % [MAX_DIMENSION, MAX_DIMENSION, MAX_DIMENSION])
	var cell_count: int = selected.x * selected.y * selected.z
	if cell_count > MAX_CELLS:
		errors.append("grid contains %d cells; maximum is %d" % [cell_count, MAX_CELLS])

	result["dims"] = selected
	result["errors"] = errors
	result["ok"] = errors.is_empty()
	return result


static func _parse_dimension_value(value: Variant) -> Dictionary:
	var dimensions: Array = []
	if value is Vector3i:
		dimensions = [value.x, value.y, value.z]
	elif value is Vector3:
		dimensions = [value.x, value.y, value.z]
	elif value is Array:
		dimensions = value
	elif value is PackedInt32Array:
		dimensions = value
	elif value is Dictionary:
		dimensions = [value.get("x"), value.get("y"), value.get("z")]
	else:
		return {"ok": false, "dims": Vector3i.ZERO}
	if dimensions.size() != 3:
		return {"ok": false, "dims": Vector3i.ZERO}
	var parsed: Array[int] = []
	for dimension: Variant in dimensions:
		if not _is_integer_value(dimension):
			return {"ok": false, "dims": Vector3i.ZERO}
		parsed.append(int(dimension))
	return {"ok": true, "dims": Vector3i(parsed[0], parsed[1], parsed[2])}


static func _extract_target(puzzle_data: Dictionary, dims: Vector3i) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"authoritative": false,
		"voxels": [],
		"errors": [],
		"source_conflict": false,
	}
	var errors: Array = []
	var target_voxels: Array = []
	var has_target: bool = puzzle_data.has("target_voxels")
	var has_cells: bool = puzzle_data.has("cells")

	if has_target:
		var target_result: Dictionary = _parse_target_voxels(puzzle_data["target_voxels"], dims)
		_append_errors_to(errors, target_result.get("errors", []))
		if bool(target_result.get("ok", false)):
			target_voxels = target_result.get("voxels", [])

	if has_cells:
		var cells_result: Dictionary = _parse_cells(puzzle_data["cells"], dims)
		_append_errors_to(errors, cells_result.get("errors", []))
		if bool(cells_result.get("ok", false)) and not has_target:
			target_voxels = cells_result.get("voxels", [])

	if has_target and has_cells and errors.is_empty():
		var cell_voxels: Array = _parse_cells(puzzle_data["cells"], dims).get("voxels", [])
		if not _same_coordinate_set(target_voxels, cell_voxels):
			result["source_conflict"] = true

	if not errors.is_empty():
		result["errors"] = errors
		return result
	result["ok"] = true
	result["authoritative"] = has_target or has_cells
	result["voxels"] = target_voxels
	result["source_conflict"] = result["source_conflict"]
	return result


static func _parse_target_voxels(value: Variant, dims: Vector3i) -> Dictionary:
	var result: Dictionary = {"ok": false, "voxels": [], "errors": []}
	var errors: Array = []
	var coordinates: Array = []
	if value is Array:
		var maximum_targets: int = dims.x * dims.y * dims.z
		if value.size() > maximum_targets:
			errors.append("target_voxels contains more coordinates than grid cells")
			result["errors"] = errors
			return result
		for index: int in range(value.size()):
			var parsed: Vector3i = _parse_coordinate(value[index], dims)
			if parsed.x < 0:
				errors.append("target_voxels[%d] is an out-of-bounds or non-integer coordinate" % index)
			else:
				coordinates.append(parsed)
	elif value is Dictionary:
		for key: Variant in value.keys():
			var parsed: Vector3i = _parse_coordinate(key, dims)
			if parsed.x < 0:
				errors.append("target_voxels contains an invalid coordinate key")
				continue
			var coordinate_value: Variant = value[key]
			if not _is_integer_value(coordinate_value) or int(coordinate_value) not in [0, 1]:
				errors.append("target_voxels dictionary values must be 0 or 1")
			elif int(coordinate_value) == 1:
				coordinates.append(parsed)
	else:
		errors.append("target_voxels must be an array or coordinate dictionary")
		result["errors"] = errors
		return result

	var seen: Dictionary = {}
	for coordinate: Vector3i in coordinates:
		if seen.has(coordinate):
			errors.append("target_voxels contains duplicate coordinate %s" % str(coordinate))
		else:
			seen[coordinate] = true
	if not errors.is_empty():
		result["errors"] = errors
		return result

	coordinates.sort_custom(_vector3i_less)
	result["ok"] = true
	result["voxels"] = coordinates
	return result


static func _parse_cells(value: Variant, dims: Vector3i) -> Dictionary:
	var result: Dictionary = {"ok": false, "voxels": [], "errors": []}
	var errors: Array = []
	var values: Array = []
	if value is Array:
		values = value
	elif value is PackedByteArray or value is PackedInt32Array:
		values = Array(value)
	else:
		errors.append("cells must be a flat array")
		result["errors"] = errors
		return result

	var expected: int = dims.x * dims.y * dims.z
	if values.size() != expected:
		errors.append("cells must contain exactly %d values" % expected)
		result["errors"] = errors
		return result
	for index: int in range(values.size()):
		var cell: Variant = values[index]
		if not _is_integer_value(cell) or int(cell) not in [0, 1]:
			errors.append("cells[%d] must be the integer 0 or 1" % index)
	if not errors.is_empty():
		result["errors"] = errors
		return result

	var voxels: Array = []
	var index: int = 0
	for z: int in range(dims.z):
		for y: int in range(dims.y):
			for x: int in range(dims.x):
				if int(values[index]) == 1:
					voxels.append(Vector3i(x, y, z))
				index += 1
	result["ok"] = true
	result["voxels"] = voxels
	return result


static func _extract_clues(puzzle_data: Dictionary, dims: Vector3i) -> Dictionary:
	var result: Dictionary = {
		"present": false,
		"contradictory": false,
		"clues": {},
		"errors": [],
		"explicit_clue_count": 0,
	}
	var errors: Array = []
	var parsed_sources: Array = []
	var present: bool = puzzle_data.has("clues") or puzzle_data.has("hints")
	result["present"] = present
	if not present:
		return result

	if puzzle_data.has("clues"):
		var clues_result: Dictionary = _parse_clue_source(puzzle_data["clues"], dims, false)
		_append_errors_to(errors, clues_result.get("errors", []))
		if bool(clues_result.get("contradictory", false)):
			result["contradictory"] = true
		if bool(clues_result.get("ok", false)):
			parsed_sources.append(clues_result.get("clues", {}))
	if puzzle_data.has("hints"):
		var hints_result: Dictionary = _parse_clue_source(puzzle_data["hints"], dims, true)
		_append_errors_to(errors, hints_result.get("errors", []))
		if bool(hints_result.get("contradictory", false)):
			result["contradictory"] = true
		if bool(hints_result.get("ok", false)):
			parsed_sources.append(hints_result.get("clues", {}))

	if not errors.is_empty() or parsed_sources.is_empty():
		result["errors"] = errors
		return result

	var selected_clues: Dictionary = parsed_sources[0]
	for source_index: int in range(1, parsed_sources.size()):
		if not _clues_match(parsed_sources[source_index], selected_clues):
			errors.append("clues and hints contain conflicting constraints")
			result["errors"] = errors
			return result
	result["clues"] = selected_clues
	result["errors"] = errors
	result["explicit_clue_count"] = _count_clues(selected_clues)
	return result


static func _parse_clue_source(value: Variant, dims: Vector3i, legacy_source: bool) -> Dictionary:
	if value is Array:
		return _parse_legacy_nested_hints(value, dims)
	if value is Dictionary:
		return _parse_modern_clue_map(value, dims, legacy_source)
	return {"ok": false, "clues": {}, "errors": ["clues/hints must be a dictionary or nested array"]}


static func _parse_modern_clue_map(value: Dictionary, dims: Vector3i, legacy_source: bool) -> Dictionary:
	var result: Dictionary = {"ok": false, "contradictory": false, "clues": {}, "errors": []}
	var errors: Array = []
	var clues: Dictionary = {}
	var found_axis: bool = false
	var allow_null_lines: bool = legacy_source and not value.has("x_axis") and not value.has("y_axis") and not value.has("z_axis")
	for raw_axis: Variant in value.keys():
		var axis_name: String = _canonical_axis_name(str(raw_axis))
		if axis_name == "":
			errors.append("unknown clue axis '%s'" % str(raw_axis))
			continue
		found_axis = true
		if clues.has(axis_name):
			errors.append("duplicate clue axis '%s'" % axis_name)
			continue
		var axis_value: Variant = value[raw_axis]
		if not axis_value is Dictionary:
			errors.append("clue axis '%s' must be a dictionary" % axis_name)
			continue
		# Dictionary line arrays use [] as an explicit zero clue.  Only the
		# three-axis nested legacy format uses [] for an omitted line.
		var axis_result: Dictionary = _parse_axis_map(axis_value, dims, axis_name, allow_null_lines)
		_append_errors_to(errors, axis_result.get("errors", []))
		if bool(axis_result.get("contradictory", false)):
			result["contradictory"] = true
		clues[axis_name] = axis_result.get("clues", {})

	if not found_axis:
		errors.append("clue dictionary does not contain x/y/z axes")
	result["clues"] = clues
	result["errors"] = errors
	result["ok"] = errors.is_empty()
	return result


static func _parse_axis_map(axis_value: Dictionary, dims: Vector3i, axis_name: String, legacy_source: bool) -> Dictionary:
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
		var key_parts: PackedStringArray = str(raw_key).split(",", false)
		var first_value: Variant = _parse_integer_text(key_parts[0]) if key_parts.size() == 2 else null
		var second_value: Variant = _parse_integer_text(key_parts[1]) if key_parts.size() == 2 else null
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
		if axis_value[raw_key] == null:
			if not legacy_source:
				errors.append("modern clue line '%s' cannot be null" % str(raw_key))
			continue
		var line_result: Dictionary = _parse_line_value(axis_value[raw_key], line_length, false)
		_append_errors_to(errors, line_result.get("errors", []))
		if bool(line_result.get("contradictory", false)):
			result["contradictory"] = true
		if bool(line_result.get("unconstrained", false)):
			continue
		if bool(line_result.get("ok", false)):
			clues[line_key] = line_result["clue"]

	result["clues"] = clues
	result["errors"] = errors
	result["ok"] = errors.is_empty()
	return result


static func _parse_legacy_nested_hints(value: Array, dims: Vector3i) -> Dictionary:
	var result: Dictionary = {"ok": false, "contradictory": false, "clues": {}, "errors": []}
	var errors: Array = []
	if value.size() != 3:
		errors.append("legacy hints must contain exactly three axes")
		result["errors"] = errors
		return result

	var clues: Dictionary = {}
	for axis_index: int in range(3):
		var axis_name: String = AXIS_KEYS[axis_index]
		var axis_value: Variant = value[axis_index]
		if not axis_value is Array:
			errors.append("legacy hints axis %d must be an array" % axis_index)
			continue
		var first_size: int = [dims.y, dims.x, dims.x][axis_index]
		var second_size: int = [dims.z, dims.z, dims.y][axis_index]
		var line_length: int = [dims.x, dims.y, dims.z][axis_index]
		var axis_clues: Dictionary = {}
		var axis_array: Array = axis_value
		if axis_array.size() > first_size:
			errors.append("legacy hints axis %d has too many rows" % axis_index)
		for first: int in range(mini(axis_array.size(), first_size)):
			var row_value: Variant = axis_array[first]
			if row_value == null:
				continue
			if not row_value is Array:
				errors.append("legacy hints axis %d row %d must be an array" % [axis_index, first])
				continue
			var row: Array = row_value
			if row.size() > second_size:
				errors.append("legacy hints axis %d row %d has too many entries" % [axis_index, first])
			for second: int in range(mini(row.size(), second_size)):
				var line_result: Dictionary = _parse_line_value(row[second], line_length, true)
				_append_errors_to(errors, line_result.get("errors", []))
				if bool(line_result.get("contradictory", false)):
					result["contradictory"] = true
				if bool(line_result.get("unconstrained", false)):
					continue
				if bool(line_result.get("ok", false)):
					axis_clues["%d,%d" % [first, second]] = line_result["clue"]
		clues[axis_name] = axis_clues

	result["clues"] = clues
	result["errors"] = errors
	result["ok"] = errors.is_empty()
	return result


static func _parse_line_value(value: Variant, line_length: int, legacy_nested: bool) -> Dictionary:
	var result: Dictionary = {"ok": false, "contradictory": false, "clue": {}, "errors": [], "unconstrained": false}
	if value == null:
		result["unconstrained"] = true
		result["ok"] = true
		return result

	if value is Array:
		var array_value: Array = value
		if array_value.is_empty():
			if legacy_nested:
				result["unconstrained"] = true
				result["ok"] = true
			else:
				var empty_clue: Dictionary = _make_exact_clue([])
				if not _validate_clue_for_length(empty_clue, line_length):
					result["errors"].append("empty clue is invalid for this line")
				else:
					result["ok"] = true
					result["clue"] = empty_clue
			return result
		if _all_numeric(array_value):
			var block_result: Dictionary = _make_block_clue(array_value, line_length)
			result["ok"] = block_result.get("ok", false)
			result["contradictory"] = block_result.get("contradictory", false)
			result["clue"] = block_result.get("clue", {})
			result["errors"] = block_result.get("errors", [])
			return result
		if array_value.size() == 1:
			return _parse_line_value(array_value[0], line_length, false)
		result["errors"].append("legacy hint line contains more than one hint object")
		return result

	if value is Dictionary:
		var dictionary_value: Dictionary = value
		if dictionary_value.has("blocks") or dictionary_value.has("total"):
			return _parse_modern_line_dictionary(dictionary_value, line_length)
		if dictionary_value.has("num"):
			return _parse_legacy_hint_dictionary(dictionary_value, line_length)
		result["errors"].append("clue object must contain total/blocks or legacy num/type")
		return result

	if _is_integer_value(value):
		var numeric_clue: Dictionary = _make_block_clue([int(value)], line_length)
		result["ok"] = numeric_clue.get("ok", false)
		result["contradictory"] = numeric_clue.get("contradictory", false)
		result["clue"] = numeric_clue.get("clue", {})
		result["errors"] = numeric_clue.get("errors", [])
		return result

	result["errors"].append("unsupported clue value")
	return result


static func _parse_modern_line_dictionary(value: Dictionary, line_length: int) -> Dictionary:
	var result: Dictionary = {"ok": false, "contradictory": false, "clue": {}, "errors": []}
	if not value.has("blocks") or not value.has("total"):
		result["errors"].append("modern clue must contain both total and blocks")
		return result
	if value.has("block_lengths_known") and not bool(value["block_lengths_known"]):
		var soft_total_result: Dictionary = _coerce_total(value["total"])
		if not bool(soft_total_result.get("ok", false)):
			result["errors"].append("clue total must be a non-negative integer")
			return result
		var group_count_value: Variant = value.get("group_count", 0)
		var min_group_count_value: Variant = value.get("min_group_count", 0)
		if not _is_integer_value(group_count_value) or not _is_integer_value(min_group_count_value) or int(group_count_value) < 0 or int(min_group_count_value) < 0:
			result["errors"].append("legacy grouped clue fields must be non-negative integers")
			return result
		var soft_clue: Dictionary = {
			"total": int(soft_total_result["value"]),
			"blocks": [],
			"block_lengths_known": false,
			"group_count": int(group_count_value),
			"min_group_count": int(min_group_count_value),
		}
		if not _validate_clue_for_length(soft_clue, line_length):
			result["contradictory"] = true
			result["errors"].append("legacy grouped clue cannot fit on this line")
			return result
		result["ok"] = true
		result["clue"] = soft_clue
		return result
	var total_result: Dictionary = _coerce_total(value["total"])
	var blocks_result: Dictionary = _coerce_blocks(value["blocks"])
	if not total_result["ok"]:
		result["errors"].append("clue total must be a non-negative integer")
	if not blocks_result["ok"]:
		result["errors"].append("clue blocks must be an array of positive integers")
	if not result["errors"].is_empty():
		return result
	var total: int = total_result["value"]
	var blocks: Array = blocks_result["value"]
	if _sum_ints(blocks) != total:
		result["contradictory"] = true
		result["errors"].append("clue total does not equal the sum of blocks")
		return result
	var clue: Dictionary = _make_exact_clue(blocks)
	if not _validate_clue_for_length(clue, line_length):
		result["contradictory"] = true
		result["errors"].append("clue blocks cannot fit on a line of length %d" % line_length)
		return result
	result["ok"] = true
	result["clue"] = clue
	return result


static func _parse_legacy_hint_dictionary(value: Dictionary, line_length: int) -> Dictionary:
	var result: Dictionary = {"ok": false, "contradictory": false, "clue": {}, "errors": []}
	if not _is_integer_value(value.get("num")):
		result["errors"].append("legacy hint num must be a non-negative integer")
		return result
	var number: int = int(value["num"])
	if number < 0:
		result["errors"].append("legacy hint num is outside the line")
		return result
	if number > line_length:
		result["contradictory"] = true
		result["errors"].append("legacy hint num is outside the line")
		return result
	var hint_type: int = 0
	if value.has("type"):
		if not _is_integer_value(value["type"]):
			result["errors"].append("legacy hint type must be an integer")
			return result
		hint_type = int(value["type"])
	if hint_type < 0 or hint_type > 2:
		result["errors"].append("legacy hint type must be 0, 1, or 2")
		return result

	if hint_type == 0:
		var exact_blocks: Array = []
		if number > 0:
			exact_blocks.append(number)
		var exact_clue: Dictionary = _make_exact_clue(exact_blocks)
		if not _validate_clue_for_length(exact_clue, line_length):
			result["contradictory"] = true
			result["errors"].append("legacy simple hint cannot fit on the line")
			return result
		result["ok"] = true
		result["clue"] = exact_clue
		return result

	var group_field: String = "group_count" if hint_type == 1 else "min_group_count"
	var clue: Dictionary = {
		"total": number,
		"blocks": [],
		"block_lengths_known": false,
		group_field: 2 if hint_type == 1 else 3,
		"legacy": true,
	}
	if not _validate_clue_for_length(clue, line_length):
		result["contradictory"] = true
		result["errors"].append("legacy grouped hint cannot fit on the line")
		return result
	result["ok"] = true
	result["clue"] = clue
	return result


static func _make_exact_clue(blocks: Array) -> Dictionary:
	var copied_blocks: Array = []
	for block: Variant in blocks:
		copied_blocks.append(int(block))
	return {
		"total": _sum_ints(copied_blocks),
		"blocks": copied_blocks,
		"block_lengths_known": true,
	}


static func _make_block_clue(blocks: Array, line_length: int) -> Dictionary:
	var result: Dictionary = {"ok": false, "contradictory": false, "clue": {}, "errors": []}
	var copied_blocks: Array = []
	for block: Variant in blocks:
		if not _is_integer_value(block) or int(block) <= 0:
			result["errors"].append("clue block lengths must be positive integers")
			return result
		copied_blocks.append(int(block))
	var clue: Dictionary = _make_exact_clue(copied_blocks)
	if not _validate_clue_for_length(clue, line_length):
		result["contradictory"] = true
		result["errors"].append("clue blocks cannot fit on a line of length %d" % line_length)
		return result
	result["ok"] = true
	result["clue"] = clue
	return result


static func _validate_clue_for_length(clue: Dictionary, line_length: int) -> bool:
	var total: int = int(clue.get("total", -1))
	if total < 0 or total > line_length:
		return false
	if bool(clue.get("block_lengths_known", true)):
		var blocks: Array = clue.get("blocks", [])
		if _sum_ints(blocks) != total:
			return false
		var minimum_length: int = total
		if not blocks.is_empty():
			minimum_length += blocks.size() - 1
		return minimum_length <= line_length
	var group_count: int = int(clue.get("group_count", 0))
	var minimum_group_count: int = int(clue.get("min_group_count", 0))
	var required_groups: int = group_count if group_count > 0 else minimum_group_count
	if required_groups <= 0 or total < required_groups:
		return false
	var maximum_groups: int = (line_length + 1) / 2
	if required_groups > maximum_groups:
		return false
	if group_count > 0 and total < group_count:
		return false
	return total + required_groups - 1 <= line_length


static func _coerce_total(value: Variant) -> Dictionary:
	if not _is_integer_value(value) or int(value) < 0:
		return {"ok": false, "value": 0}
	return {"ok": true, "value": int(value)}


static func _coerce_blocks(value: Variant) -> Dictionary:
	var values: Array = []
	if value is Array:
		values = value
	elif value is PackedInt32Array:
		values = Array(value)
	else:
		return {"ok": false, "value": []}
	for block: Variant in values:
		if not _is_integer_value(block) or int(block) <= 0:
			return {"ok": false, "value": []}
	return {"ok": true, "value": values}


static func _derive_clues_from_set(dims: Vector3i, target_set: Dictionary) -> Dictionary:
	var clues: Dictionary = {}
	for axis_index: int in range(3):
		var axis_name: String = AXIS_KEYS[axis_index]
		var first_size: int = [dims.y, dims.x, dims.x][axis_index]
		var second_size: int = [dims.z, dims.z, dims.y][axis_index]
		var axis_clues: Dictionary = {}
		for first: int in range(first_size):
			for second: int in range(second_size):
				var values: Array = []
				for line_index: int in range([dims.x, dims.y, dims.z][axis_index]):
					var coordinate: Vector3i = _line_coordinate(axis_index, first, second, line_index)
					values.append(1 if target_set.has(coordinate) else 0)
				var blocks: Array = []
				var run_length: int = 0
				for value: int in values:
					if value == 1:
						run_length += 1
					elif run_length > 0:
						blocks.append(run_length)
						run_length = 0
				if run_length > 0:
					blocks.append(run_length)
				axis_clues["%d,%d" % [first, second]] = {
					"total": _sum_ints(blocks),
					"blocks": blocks,
				}
		clues[axis_name] = axis_clues
	return clues


static func _line_coordinate(axis_index: int, first: int, second: int, line_index: int) -> Vector3i:
	if axis_index == 0:
		return Vector3i(line_index, first, second)
	if axis_index == 1:
		return Vector3i(first, line_index, second)
	return Vector3i(first, second, line_index)


static func _build_canonical_puzzle(puzzle_data: Dictionary, dims: Vector3i, target_voxels: Array, clues: Dictionary) -> Dictionary:
	var canonical: Dictionary = {}
	for key: Variant in puzzle_data.keys():
		if _DROPPED_KEYS.has(key):
			continue
		canonical[key] = puzzle_data[key]
	var dimensions: Array = [dims.x, dims.y, dims.z]
	canonical["dims"] = dimensions.duplicate()
	canonical["grid_size"] = dimensions.duplicate()
	var target_arrays: Array = []
	for coordinate: Vector3i in target_voxels:
		target_arrays.append([coordinate.x, coordinate.y, coordinate.z])
	canonical["target_voxels"] = target_arrays
	canonical["clues"] = clues.duplicate(true)
	canonical["voxel_count"] = target_voxels.size()
	canonical["solvable"] = true
	return canonical


static func _attach_canonical(result: Dictionary, canonical: Dictionary) -> void:
	result["puzzle"] = canonical
	result["canonical"] = canonical
	# Make the result convenient for callers that want to inspect normalized
	# fields without unwrapping the puzzle member.
	for key: String in ["dims", "grid_size", "target_voxels", "clues", "voxel_count"]:
		if canonical.has(key):
			result[key] = canonical[key]
	result["canonical_puzzle"] = canonical


static func _clues_match(stored: Dictionary, derived: Dictionary) -> bool:
	for axis_name: String in AXIS_KEYS:
		var expected_axis: Dictionary = derived.get(axis_name, {})
		var actual_axis_value: Variant = stored.get(axis_name, null)
		if not actual_axis_value is Dictionary:
			return false
		var actual_axis: Dictionary = actual_axis_value
		if actual_axis.size() != expected_axis.size():
			return false
		for raw_key: Variant in actual_axis.keys():
			if not raw_key is String or not expected_axis.has(raw_key):
				return false
			var expected_line: Dictionary = expected_axis[raw_key]
			var actual_line: Variant = actual_axis[raw_key]
			if not actual_line is Dictionary or not _line_values_equal(actual_line, expected_line):
				return false
	return true


static func _line_values_equal(actual: Dictionary, expected: Dictionary) -> bool:
	if not _is_integer_value(actual.get("total")) or int(actual["total"]) != int(expected.get("total", -1)):
		return false
	var actual_blocks_value: Variant = actual.get("blocks")
	if not actual_blocks_value is Array and not actual_blocks_value is PackedInt32Array:
		return false
	var actual_blocks: Array = Array(actual_blocks_value)
	var expected_blocks: Array = expected.get("blocks", [])
	if actual_blocks.size() != expected_blocks.size():
		return false
	for index: int in range(expected_blocks.size()):
		if not _is_integer_value(actual_blocks[index]) or int(actual_blocks[index]) != int(expected_blocks[index]):
			return false
	return true


static func _count_clues(clues: Dictionary) -> int:
	var count: int = 0
	for axis_name: String in AXIS_KEYS:
		var axis_value: Variant = clues.get(axis_name, {})
		if axis_value is Dictionary:
			count += (axis_value as Dictionary).size()
	return count


static func _canonical_axis_name(value: String) -> String:
	var normalized: String = value.to_lower()
	if normalized == "x_axis" or normalized == "x":
		return "x_axis"
	if normalized == "y_axis" or normalized == "y":
		return "y_axis"
	if normalized == "z_axis" or normalized == "z":
		return "z_axis"
	return ""


static func _solution_is_complete(dims: Vector3i, solution: Dictionary) -> bool:
	if solution.size() != dims.x * dims.y * dims.z:
		return false
	for x: int in range(dims.x):
		for y: int in range(dims.y):
			for z: int in range(dims.z):
				if not solution.has(Vector3i(x, y, z)) or not (solution[Vector3i(x, y, z)] is bool):
					return false
	return true


static func _solution_matches_target(solution: Dictionary, target_voxels: Array) -> bool:
	var target_set: Dictionary = {}
	for coordinate: Variant in target_voxels:
		var parsed: Vector3i = _coerce_coordinate(coordinate, Vector3i(-1, -1, -1))
		target_set[parsed] = true
	for coordinate: Vector3i in target_set.keys():
		if not solution.has(coordinate) or not bool(solution[coordinate]):
			return false
	for coordinate: Vector3i in solution.keys():
		var is_target: bool = target_set.has(coordinate)
		if bool(solution[coordinate]) != is_target:
			return false
	return true


static func _target_authoritative_solver_result(dims: Vector3i, target_voxels: Array) -> Dictionary:
	var target_solution: Dictionary = {}
	var target_set: Dictionary = {}
	for coordinate: Vector3i in target_voxels:
		target_set[coordinate] = true
	for x: int in range(dims.x):
		for y: int in range(dims.y):
			for z: int in range(dims.z):
				var coordinate: Vector3i = Vector3i(x, y, z)
				target_solution[coordinate] = target_set.has(coordinate)
	return {
		"status": STATUS_SOLVED,
		"is_solved": true,
		"is_ambiguous": false,
		"is_contradictory": false,
		"is_valid": true,
		"valid": true,
		"solution": target_solution,
		"states": {},
		"solution_count": 1,
		"unknown_count": 0,
		"errors": [],
		"deduced_from_target": true,
		"target_authoritative": true,
	}


static func _target_from_solution(solution: Dictionary) -> Array:
	var coordinates: Array = []
	for coordinate: Vector3i in solution.keys():
		if bool(solution[coordinate]):
			coordinates.append(coordinate)
	coordinates.sort_custom(_vector3i_less)
	return coordinates


static func _same_coordinate_set(first: Array, second: Array) -> bool:
	if first.size() != second.size():
		return false
	var first_set: Dictionary = {}
	for coordinate: Variant in first:
		first_set[_coerce_coordinate(coordinate, Vector3i(-1, -1, -1))] = true
	for coordinate: Variant in second:
		var parsed: Vector3i = _coerce_coordinate(coordinate, Vector3i(-1, -1, -1))
		if not first_set.has(parsed):
			return false
	return true


static func _parse_coordinate(value: Variant, dims: Vector3i) -> Vector3i:
	var components: Array = []
	if value is Vector3i:
		components = [value.x, value.y, value.z]
	elif value is Vector3:
		components = [value.x, value.y, value.z]
	elif value is Array:
		components = value
	elif value is PackedInt32Array:
		components = Array(value)
	elif value is Dictionary:
		components = [value.get("x"), value.get("y"), value.get("z")]
	else:
		return Vector3i(-1, -1, -1)
	if components.size() != 3:
		return Vector3i(-1, -1, -1)
	var parsed: Array[int] = []
	for component: Variant in components:
		if not _is_integer_value(component):
			return Vector3i(-1, -1, -1)
		parsed.append(int(component))
	var coordinate: Vector3i = Vector3i(parsed[0], parsed[1], parsed[2])
	if coordinate.x < 0 or coordinate.x >= dims.x or coordinate.y < 0 or coordinate.y >= dims.y or coordinate.z < 0 or coordinate.z >= dims.z:
		return Vector3i(-1, -1, -1)
	return coordinate


static func _coerce_coordinate(value: Variant, fallback: Vector3i) -> Vector3i:
	var parsed: Vector3i = _parse_coordinate(value, Vector3i(1 << 20, 1 << 20, 1 << 20))
	if parsed.x < 0:
		return fallback
	return parsed


static func _vector3i_less(first: Vector3i, second: Vector3i) -> bool:
	if first.x != second.x:
		return first.x < second.x
	if first.y != second.y:
		return first.y < second.y
	return first.z < second.z


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


static func _append_errors_to(target: Array, values: Variant) -> void:
	if not values is Array:
		return
	for value: Variant in values:
		target.append(str(value))


static func _string_array(values: Array) -> Array:
	var result: Array = []
	for value: Variant in values:
		result.append(str(value))
	return result
