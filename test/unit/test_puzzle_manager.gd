extends GutTest

const PuzzleManagerClass = preload("res://scripts/PuzzleManager.gd")


func test_catalog_loads_validated_puzzles() -> void:
	var manager: Node = PuzzleManagerClass.new()
	add_child_autoqfree(manager)
	var catalog: Array = manager.call("load_catalog")
	assert_gt(catalog.size(), 0)
	var validation: Dictionary = manager.call("validate_catalog")
	assert_true(bool(validation.get("ok", false)))
	for puzzle: Dictionary in catalog:
		assert_true(puzzle.has("dims"))
		assert_true(puzzle.has("target_voxels"))
		assert_true(puzzle.has("clues"))
	await get_tree().process_frame


func test_round_selection_is_deterministic_and_depth_aware() -> void:
	var manager: Node = PuzzleManagerClass.new()
	add_child_autoqfree(manager)
	var easy: Dictionary = manager.call("get_puzzle_for_round", 17, 1, "easy")
	var easy_again: Dictionary = manager.call("get_puzzle_for_round", 17, 1, "easy")
	assert_eq(easy, easy_again)
	assert_eq(str(easy.get("difficulty_tier", "")), "easy")
	var hard: Dictionary = manager.call("get_puzzle_for_round", 17, 31, "endless")
	assert_eq(str(hard.get("difficulty_tier", "")), "hard")
	await get_tree().process_frame


func test_shipping_catalog_passes_strict_validation() -> void:
	var manager: Node = get_node_or_null("/root/PuzzleManager")
	assert_not_null(manager)
	var report: Dictionary = manager.call("validate_catalog")
	assert_true(bool(report.get("ok", false)), str(report.get("errors", [])))
	assert_true(int(report.get("count", 0)) > 0)


func test_depth_dimension_contract() -> void:
	var manager: Node = PuzzleManagerClass.new()
	add_child_autoqfree(manager)
	assert_eq(manager.call("get_dimensions_for_depth", 1), Vector3i(3, 3, 3))
	assert_eq(manager.call("get_dimensions_for_depth", 10), Vector3i(3, 3, 3))
	assert_eq(manager.call("get_dimensions_for_depth", 11), Vector3i(4, 4, 4))
	assert_eq(manager.call("get_dimensions_for_depth", 30), Vector3i(4, 4, 4))
	assert_eq(manager.call("get_dimensions_for_depth", 31), Vector3i(5, 5, 5))
	await get_tree().process_frame
