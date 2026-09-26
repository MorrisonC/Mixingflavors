extends GutTest

const PuzzleDataValidatorClass = preload("res://scripts/PuzzleDataValidator.gd")
const SolvabilityValidatorClass = preload("res://scripts/SolvabilityValidator.gd")
const PuzzleManagerClass = preload("res://scripts/PuzzleManager.gd")


func test_contradiction_is_checked_on_an_already_known_line() -> void:
	var puzzle: Dictionary = {
		"dims": [1, 1, 2],
		"clues": {
			"x_axis": {
				"0,0": {"total": 1, "blocks": [1]},
				"0,1": {"total": 0, "blocks": []},
			},
			"z_axis": {
				"0,0": {"total": 0, "blocks": []},
			},
		},
	}
	var result: Dictionary = PuzzleDataValidatorClass.analyze_puzzle(puzzle)
	assert_eq(str(result.get("status", "")), PuzzleDataValidatorClass.STATUS_CONTRADICTORY)
	assert_false(bool(result.get("ok", true)))
	assert_true(bool(result.get("solver_result", {}).get("is_contradictory", false)))


func test_dimensions_coordinates_and_cells_are_validated_at_boundary() -> void:
	var out_of_bounds: Dictionary = PuzzleDataValidatorClass.analyze_puzzle({
		"dims": [2, 1, 1],
		"target_voxels": [[2, 0, 0]],
	})
	assert_eq(str(out_of_bounds.get("status", "")), PuzzleDataValidatorClass.STATUS_INVALID)

	var bad_dimension: Dictionary = PuzzleDataValidatorClass.analyze_puzzle({
		"dims": [0, 1, 1],
		"cells": [],
	})
	assert_eq(str(bad_dimension.get("status", "")), PuzzleDataValidatorClass.STATUS_INVALID)

	var bad_cells: Dictionary = PuzzleDataValidatorClass.analyze_puzzle({
		"dims": [2, 2, 1],
		"cells": [1, 0, 0],
	})
	assert_eq(str(bad_cells.get("status", "")), PuzzleDataValidatorClass.STATUS_INVALID)
	assert_true(str(bad_cells.get("errors", [])).contains("exactly 4"))

	var duplicate_coordinate: Dictionary = PuzzleDataValidatorClass.analyze_puzzle({
		"dims": [2, 1, 1],
		"target_voxels": [[0, 0, 0], [0, 0, 0]],
	})
	assert_eq(str(duplicate_coordinate.get("status", "")), PuzzleDataValidatorClass.STATUS_INVALID)
	assert_true(str(duplicate_coordinate.get("errors", [])).contains("duplicate"))

	var wrong_coordinate_type: Dictionary = PuzzleDataValidatorClass.analyze_puzzle({
		"dims": [2, 1, 1],
		"target_voxels": [["0", 0, 0]],
	})
	assert_eq(str(wrong_coordinate_type.get("status", "")), PuzzleDataValidatorClass.STATUS_INVALID)

	var over_cap: Dictionary = PuzzleDataValidatorClass.analyze_puzzle({
		"grid_size": [6, 1, 1],
		"target_voxels": [],
	})
	assert_eq(str(over_cap.get("status", "")), PuzzleDataValidatorClass.STATUS_INVALID)


func test_ambiguous_hints_never_create_a_target() -> void:
	var puzzle: Dictionary = {
		"dims": [2, 2, 1],
		"clues": {
			"x_axis": {
				"0,0": {"total": 1, "blocks": [1]},
				"1,0": {"total": 1, "blocks": [1]},
			},
			"y_axis": {
				"0,0": {"total": 1, "blocks": [1]},
				"1,0": {"total": 1, "blocks": [1]},
			},
		},
	}
	var result: Dictionary = PuzzleDataValidatorClass.analyze_puzzle(puzzle)
	assert_eq(str(result.get("status", "")), PuzzleDataValidatorClass.STATUS_AMBIGUOUS)
	assert_false(bool(result.get("ok", true)))
	assert_false(result.get("puzzle", {}).has("target_voxels"))
	assert_true(result.get("solver_result", {}).get("solution", {}).is_empty())


func test_legacy_nested_hints_are_normalized_only_after_unique_solution() -> void:
	var puzzle: Dictionary = {
		"dims": [1, 1, 2],
		"hints": [
			[[{"num": 1, "type": 0}, {"num": 0, "type": 0}]],
			[[{"num": 1, "type": 0}, {"num": 0, "type": 0}]],
			[[{"num": 1, "type": 0}]],
		],
	}
	var result: Dictionary = PuzzleDataValidatorClass.analyze_puzzle(puzzle)
	assert_true(bool(result.get("ok", false)))
	assert_eq(result.get("target_voxels", []), [[0, 0, 0]])
	assert_true(result.get("puzzle", {}).has("clues"))
	assert_false(result.get("puzzle", {}).has("hints"))


func test_cells_and_grid_size_normalize_to_canonical_target_and_clues() -> void:
	var puzzle: Dictionary = {
		"grid_size": [2, 1, 1],
		"cells": [1, 0],
	}
	var result: Dictionary = PuzzleDataValidatorClass.analyze_puzzle(puzzle)
	assert_true(bool(result.get("ok", false)))
	var canonical: Dictionary = result.get("puzzle", {})
	assert_eq(canonical.get("dims", []), [2, 1, 1])
	assert_eq(canonical.get("grid_size", []), [2, 1, 1])
	assert_eq(canonical.get("target_voxels", []), [[0, 0, 0]])
	assert_true(canonical.has("clues"))
	assert_false(canonical.has("cells"))
	assert_false(canonical.has("hints"))
	assert_eq(canonical.get("clues", {}).get("x_axis", {}).get("0,0", {}).get("total", -1), 1)


func test_target_authoritative_puzzles_repair_bad_stored_clues() -> void:
	var puzzle: Dictionary = {
		"dims": [1, 1, 1],
		"target_voxels": [[0, 0, 0]],
		"clues": {
			"x_axis": {"0,0": {"total": 0, "blocks": []}},
			"y_axis": {"0,0": {"total": 0, "blocks": []}},
			"z_axis": {"0,0": {"total": 0, "blocks": []}},
		},
	}
	var result: Dictionary = PuzzleDataValidatorClass.analyze_puzzle(puzzle)
	assert_true(bool(result.get("ok", false)))
	assert_true(int(result.get("repair_count", 0)) > 0)
	var canonical: Dictionary = result.get("puzzle", {})
	assert_eq(canonical.get("clues", {}).get("x_axis", {}).get("0,0", {}).get("total", -1), 1)
	assert_eq(canonical.get("clues", {}).get("y_axis", {}).get("0,0", {}).get("total", -1), 1)
	assert_eq(canonical.get("clues", {}).get("z_axis", {}).get("0,0", {}).get("total", -1), 1)
	# The strict compatibility API still reports the supplied contradiction;
	# repair is an explicit normalizer operation, never an implicit guess.
	assert_false(SolvabilityValidatorClass.is_puzzle_solvable(puzzle))


func test_runtime_catalog_returns_canonical_production_schema() -> void:
	var manager: Node = PuzzleManagerClass.new()
	add_child_autoqfree(manager)
	var catalog: Array = manager.call("load_catalog")
	assert_gt(catalog.size(), 0)
	for puzzle: Dictionary in catalog:
		assert_true(puzzle.has("dims"))
		assert_true(puzzle.has("grid_size"))
		assert_true(puzzle.has("target_voxels"))
		assert_true(puzzle.has("clues"))
		assert_false(puzzle.has("hints"))
		assert_false(puzzle.has("cells"))
		var dims: Array = puzzle.get("dims", [])
		assert_true(int(dims[0]) <= PuzzleDataValidatorClass.MAX_DIMENSION)
		assert_true(int(dims[1]) <= PuzzleDataValidatorClass.MAX_DIMENSION)
		assert_true(int(dims[2]) <= PuzzleDataValidatorClass.MAX_DIMENSION)
	assert_eq(manager.call("get_catalog_size"), catalog.size())
