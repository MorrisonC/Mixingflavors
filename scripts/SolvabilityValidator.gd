extends Node
class_name SolvabilityValidator

## Compatibility-facing wrapper around the central puzzle boundary.
## All schema parsing, repair, and uniqueness checks live in
## PuzzleDataValidator so callers cannot accidentally use a weaker path.

const PuzzleDataValidatorClass = preload("res://scripts/PuzzleDataValidator.gd")

## Checks the puzzle as supplied.  Repair is an explicit normalizer operation;
## this preserves the legacy boolean contract for contradictory stored data.
static func is_puzzle_solvable(puzzle_data: Dictionary) -> bool:
	var result: Dictionary = PuzzleDataValidatorClass.analyze_puzzle(puzzle_data, true, false)
	return bool(result.get("ok", false))

static func is_puzzle_solvable_after_normalization(puzzle_data: Dictionary) -> bool:
	var result: Dictionary = PuzzleDataValidatorClass.analyze_puzzle(puzzle_data, true, true)
	return bool(result.get("ok", false))


static func analyze_puzzle(puzzle_data: Dictionary) -> Dictionary:
	return PuzzleDataValidatorClass.analyze_puzzle(puzzle_data, true)

static func validate_puzzle(puzzle_data: Dictionary) -> Dictionary:
	return PuzzleDataValidatorClass.analyze_puzzle(puzzle_data, true, false)

static func validate_strict(puzzle_data: Dictionary) -> Dictionary:
	return PuzzleDataValidatorClass.analyze_puzzle(puzzle_data, true, false)

static func validate(puzzle_data: Dictionary) -> Dictionary:
	return analyze_puzzle(puzzle_data)

static func analyze(puzzle_data: Dictionary) -> Dictionary:
	return analyze_puzzle(puzzle_data)

static func normalize(puzzle_data: Dictionary) -> Dictionary:
	return analyze_puzzle(puzzle_data)

static func normalize_puzzle(puzzle_data: Dictionary, require_unique: bool = true) -> Dictionary:
	return PuzzleDataValidatorClass.normalize_puzzle(puzzle_data, require_unique)

static func canonicalize_puzzle(puzzle_data: Dictionary, require_unique: bool = true) -> Dictionary:
	return PuzzleDataValidatorClass.canonicalize_puzzle(puzzle_data, require_unique)

static func normalize_canonical(puzzle_data: Dictionary, require_unique: bool = true) -> Dictionary:
	return PuzzleDataValidatorClass.normalize_canonical(puzzle_data, require_unique)

static func get_status(puzzle_data: Dictionary) -> String:
	return str(analyze_puzzle(puzzle_data).get("status", PuzzleDataValidatorClass.STATUS_INVALID))


static func derive_clues(dims: Vector3i, target_voxels: Array) -> Dictionary:
	return PuzzleDataValidatorClass.derive_clues(dims, target_voxels)
