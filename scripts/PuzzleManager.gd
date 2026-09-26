extends Node
class_name PuzzleManagerService

## Fast, deterministic access to the shipped puzzle catalog.
##
## The full theme library remains available as source data, but the Web build
## only loads this small validated catalog at startup. This keeps the first
## gauntlet round responsive instead of parsing and solving thousands of JSON
## puzzles while the player is choosing a difficulty.

const CATALOG_PATH: String = "res://assets/puzzles/gauntlet_catalog.json"
const FALLBACK_PATH: String = "res://data/puzzles/tutorial_star.json"
## Single source of truth for "which catalog is this". The Daily Challenge bakes a
## catalog version into its identity (and therefore into its seed and puzzle
## sequence), so a second independent constant could drift out of step and change
## the daily's puzzles while its recorded identity stayed the same. Bump this
## one constant and the daily identity follows.
const CATALOG_VERSION: int = 1
## Version of the gauntlet rules themselves (scoring, banking, difficulty curve).
## Also part of the daily identity.
const RULESET_VERSION: int = 1
const VALIDATOR: GDScript = preload("res://scripts/PuzzleDataValidator.gd")
const DIFFICULTY_CURVE: GDScript = preload("res://scripts/DifficultyCurve.gd")

var _catalog: Array[Dictionary] = []
var _catalog_loaded: bool = false
var _load_error: String = ""


func _ready() -> void:
	load_catalog()


func load_catalog(force_reload: bool = false) -> Array[Dictionary]:
	if _catalog_loaded and not force_reload:
		return get_catalog()

	_catalog.clear()
	_load_error = ""
	var parsed: Variant = _read_json(CATALOG_PATH)
	if parsed is Dictionary:
		var raw_puzzles: Variant = (parsed as Dictionary).get("puzzles", [])
		if raw_puzzles is Array:
			for raw_puzzle: Variant in raw_puzzles:
				_add_catalog_puzzle(raw_puzzle)

	if _catalog.is_empty():
		var fallback: Variant = _read_json(FALLBACK_PATH)
		if fallback is Dictionary:
			_add_validated_puzzle(fallback)

	_catalog_loaded = true
	if _catalog.is_empty() and _load_error.is_empty():
		_load_error = "No validated puzzles were found in the runtime catalog"
	return get_catalog()


func get_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for puzzle: Dictionary in _catalog:
		result.append(puzzle.duplicate(true))
	return result


func get_catalog_size() -> int:
	load_catalog()
	return _catalog.size()


func get_catalog_version() -> int:
	return CATALOG_VERSION


func get_catalog_fingerprint() -> String:
	load_catalog()
	return JSON.stringify(_catalog).sha256_text()


func get_load_error() -> String:
	return _load_error


func get_puzzles_for_theme(theme_name: String) -> Array[Dictionary]:
	load_catalog()
	var normalized_theme: String = theme_name.strip_edges().to_lower()
	var result: Array[Dictionary] = []
	for puzzle: Dictionary in _catalog:
		if str(puzzle.get("theme", "")).to_lower() == normalized_theme:
			result.append(puzzle.duplicate(true))
	return result


func get_puzzles_for_tier(tier: String) -> Array[Dictionary]:
	load_catalog()
	var normalized_tier: String = tier.strip_edges().to_lower()
	var result: Array[Dictionary] = []
	for puzzle: Dictionary in _catalog:
		if str(puzzle.get("difficulty_tier", "")).to_lower() == normalized_tier:
			result.append(puzzle.duplicate(true))
	return result


func get_tier_for_depth(depth: int) -> String:
	return DIFFICULTY_CURVE.get_tier_for_depth(depth, "endless")


func get_dimensions_for_depth(depth: int) -> Vector3i:
	return DIFFICULTY_CURVE.get_dimensions_for_depth(depth)


func get_puzzle_for_round(run_seed: int, depth: int, difficulty: String = "endless") -> Dictionary:
	load_catalog()
	if _catalog.is_empty():
		return {}

	var requested_tier: String = difficulty.to_lower()
	if difficulty.to_lower() == "endless":
		requested_tier = get_tier_for_depth(depth)
	elif not (requested_tier in ["easy", "medium", "hard"]):
		requested_tier = "medium"

	var candidates: Array[Dictionary] = get_puzzles_for_tier(requested_tier)
	if candidates.is_empty():
		candidates = get_catalog()

	if difficulty.to_lower() == "endless":
		var preferred_dimensions: Vector3i = get_dimensions_for_depth(depth)
		var dimension_matches: Array[Dictionary] = []
		for puzzle: Dictionary in candidates:
			var dimensions: Array = puzzle.get("dims", puzzle.get("grid_size", []))
			if dimensions.size() == 3 and int(dimensions[0]) == preferred_dimensions.x and int(dimensions[1]) == preferred_dimensions.y and int(dimensions[2]) == preferred_dimensions.z:
				dimension_matches.append(puzzle)
		if not dimension_matches.is_empty():
			candidates = dimension_matches

	if candidates.is_empty():
		return {}

	var tier_offset: int = {"easy": 0, "medium": 101, "hard": 202}.get(requested_tier, 303)
	var mixed_index: int = CATALOG_VERSION * 1009 + run_seed * 31 + maxi(depth, 1) * 17 + tier_offset
	if mixed_index < 0:
		mixed_index = -mixed_index
	var selected: Dictionary = candidates[mixed_index % candidates.size()]
	return selected.duplicate(true)


func get_fallback_puzzle() -> Dictionary:
	load_catalog()
	if not _catalog.is_empty():
		return _catalog[0].duplicate(true)
	var fallback: Variant = _read_json(FALLBACK_PATH)
	return fallback.duplicate(true) if fallback is Dictionary else {}


func validate_catalog() -> Dictionary:
	load_catalog()
	var errors: Array = []
	if not _load_error.is_empty():
		errors.append(_load_error)
	if _catalog.is_empty():
		errors.append("Runtime catalog is empty")
	var seen_ids: Dictionary = {}
	for puzzle: Dictionary in _catalog:
		var puzzle_id: String = str(puzzle.get("id", "")).strip_edges()
		if puzzle_id.is_empty():
			errors.append("Catalog contains a puzzle without an id")
		elif seen_ids.has(puzzle_id):
			errors.append("Catalog contains duplicate puzzle id '%s'" % puzzle_id)
		else:
			seen_ids[puzzle_id] = true
		# Runtime validation is a release gate, not an assertion supplied by a
		# JSON flag. Strict mode rejects malformed or ambiguous stored clues.
		var analysis: Dictionary = VALIDATOR.analyze_puzzle(puzzle, true, false)
		if not bool(analysis.get("ok", false)):
			errors.append("Catalog puzzle '%s' failed strict validation: %s" % [puzzle_id, str(analysis.get("errors", analysis.get("status", "unknown")))])
	return {"ok": errors.is_empty(), "errors": errors, "count": _catalog.size()}


func _add_catalog_puzzle(raw_puzzle: Variant) -> void:
	if not raw_puzzle is Dictionary:
		_load_error = "Catalog contains a non-dictionary puzzle entry"
		return
	var puzzle: Dictionary = raw_puzzle as Dictionary
	var dimensions: Variant = puzzle.get("dims", puzzle.get("grid_size", []))
	var targets: Variant = puzzle.get("target_voxels", [])
	var clues: Variant = puzzle.get("clues", {})
	if not dimensions is Array or (dimensions as Array).size() != 3 or not targets is Array or not clues is Dictionary:
		_load_error = "Catalog puzzle '%s' has an invalid runtime shape" % str(puzzle.get("id", "unknown"))
		return
	_catalog.append(puzzle.duplicate(true))


func _add_validated_puzzle(raw_puzzle: Variant) -> void:
	if not raw_puzzle is Dictionary:
		_load_error = "Catalog contains a non-dictionary puzzle entry"
		return
	var analysis: Dictionary = VALIDATOR.analyze_puzzle(raw_puzzle as Dictionary, true, true)
	if not bool(analysis.get("ok", false)):
		_load_error = "Catalog puzzle '%s' was rejected: %s" % [str((raw_puzzle as Dictionary).get("id", "unknown")), str(analysis.get("errors", []))]
		return
	var canonical: Variant = analysis.get("puzzle", {})
	if canonical is Dictionary and not (canonical as Dictionary).is_empty():
		_catalog.append((canonical as Dictionary).duplicate(true))


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_load_error = "Puzzle data file does not exist: %s" % path
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_load_error = "Could not open puzzle data file: %s" % path
		return null
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_load_error = "Invalid JSON in puzzle data file: %s" % path
	return parsed
