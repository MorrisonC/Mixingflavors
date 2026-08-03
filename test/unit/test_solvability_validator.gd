extends GutTest

const SolvabilityValidator = preload("res://scripts/SolvabilityValidator.gd")

func test_valid_solvable_puzzle():
	var valid_puzzle = {
		"dims": [2, 2, 2],
		"target_voxels": [[0,0,0], [1,1,1]],
		"hints": {
			"x": {
				"0,0": [1],
				"0,1": [],
				"1,0": [],
				"1,1": [1]
			},
			"y": {
				"0,0": [1],
				"0,1": [],
				"1,0": [],
				"1,1": [1]
			},
			"z": {
				"0,0": [1],
				"0,1": [],
				"1,0": [],
				"1,1": [1]
			}
		}
	}
	assert_true(SolvabilityValidator.is_puzzle_solvable(valid_puzzle))

func test_unsolvable_puzzle():
	# A 2x2 grid with 2 corners filled is notoriously ambiguous (multiple valid solutions possible) without enough clues
	var ambiguous_puzzle = {
		"dims": [2, 2, 1],
		"target_voxels": [[0,0,0], [1,1,0]],
		"hints": {
			"x": {
				"0,0": [1],
				"1,0": [1]
			},
			"y": {
				"0,0": [1],
				"1,0": [1]
			},
			"z": {
				"0,0": [1],
				"0,1": [1],
				"1,0": [1],
				"1,1": [1]
			}
		}
	}
	# Our validator does not support guessing, so an ambiguous puzzle will fail to solve completely
	assert_false(SolvabilityValidator.is_puzzle_solvable(ambiguous_puzzle))
