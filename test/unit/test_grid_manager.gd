extends GutTest

const GridManagerScene = preload("res://scenes/VoxelLogic.tscn")
var grid_manager

func before_each():
	grid_manager = GridManagerScene.instantiate()
	grid_manager.base_grid_size = 2
	add_child(grid_manager)

func after_each():
	grid_manager.queue_free()

func test_build_grid():
	assert_eq(grid_manager.blocks.size(), 8, "Grid should have 8 blocks (2x2x2)")

func test_slicing_hides_blocks():
	assert_false(grid_manager.voxel_states[Vector3i(1, 1, 1)].get("is_hidden_by_slice", false), "Block should not be hidden initially")

	grid_manager.slice_max = Vector3i(0, 0, 0)
	grid_manager._update_slicing()

	assert_true(grid_manager.voxel_states[Vector3i(1, 1, 1)].get("is_hidden_by_slice", false), "Block should be hidden after slice")

func test_is_cell_correct_logic():
	var target_pos = Vector3i(0, 0, 0)
	var non_target_pos = Vector3i(1, 1, 1)

	grid_manager.target_solution[target_pos] = true
	grid_manager.target_solution[non_target_pos] = false

	# Intact target cell -> Correct
	assert_true(grid_manager.is_cell_correct(target_pos), "Intact target cell must be correct")

	# Intact non-target cell -> Incorrect
	assert_false(grid_manager.is_cell_correct(non_target_pos), "Intact non-target cell must be incorrect")

	# Destroyed non-target cell -> Correct
	grid_manager.hammer_cell(non_target_pos)
	assert_true(grid_manager.is_cell_correct(non_target_pos), "Destroyed non-target cell must be correct")

	# Destroyed target cell -> Incorrect
	grid_manager.hammer_cell(target_pos)
	assert_false(grid_manager.is_cell_correct(target_pos), "Destroyed target cell must be incorrect")