extends RefCounted
class_name PuzzleNormalizer

## Compatibility-facing name for the central puzzle boundary.  The
## implementation lives in PuzzleDataValidator so Registry and validators use
## exactly the same rules.

const PuzzleDataValidatorClass = preload("res://scripts/PuzzleDataValidator.gd")
const MAX_DIMENSION: int = PuzzleDataValidatorClass.MAX_DIMENSION
const MAX_CELLS: int = PuzzleDataValidatorClass.MAX_CELLS
const STATUS_SOLVED: String = PuzzleDataValidatorClass.STATUS_SOLVED
const STATUS_AMBIGUOUS: String = PuzzleDataValidatorClass.STATUS_AMBIGUOUS
const STATUS_CONTRADICTORY: String = PuzzleDataValidatorClass.STATUS_CONTRADICTORY
const STATUS_INVALID: String = PuzzleDataValidatorClass.STATUS_INVALID

static func analyze_puzzle(puzzle_data: Dictionary, require_unique: bool = true, repair_target_clues: bool = true) -> Dictionary:
	return PuzzleDataValidatorClass.analyze_puzzle(puzzle_data, require_unique, repair_target_clues)

static func normalize(puzzle_data: Dictionary, require_unique: bool = true) -> Dictionary:
	return analyze_puzzle(puzzle_data, require_unique, true)

static func normalize_puzzle(puzzle_data: Dictionary, require_unique: bool = true) -> Dictionary:
	return PuzzleDataValidatorClass.normalize_puzzle(puzzle_data, require_unique)

static func canonicalize_puzzle(puzzle_data: Dictionary, require_unique: bool = true) -> Dictionary:
	return PuzzleDataValidatorClass.canonicalize_puzzle(puzzle_data, require_unique)

static func normalize_canonical(puzzle_data: Dictionary, require_unique: bool = true) -> Dictionary:
	return PuzzleDataValidatorClass.normalize_canonical(puzzle_data, require_unique)

static func validate(puzzle_data: Dictionary) -> Dictionary:
	return analyze_puzzle(puzzle_data, true)

static func validate_puzzle(puzzle_data: Dictionary) -> bool:
	return PuzzleDataValidatorClass.validate_puzzle(puzzle_data)

static func is_valid(puzzle_data: Dictionary) -> bool:
	return validate_puzzle(puzzle_data)

static func derive_clues(dims: Vector3i, target_voxels: Array) -> Dictionary:
	return PuzzleDataValidatorClass.derive_clues(dims, target_voxels)
