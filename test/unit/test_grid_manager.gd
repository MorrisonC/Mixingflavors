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
	assert_true(grid_manager.blocks[Vector3i(1, 1, 1)].visible, "Block should be visible initially")

	grid_manager.slice_max = Vector3i(0, 0, 0)
	grid_manager._update_slicing()

	assert_false(grid_manager.blocks[Vector3i(1, 1, 1)].visible, "Block should be hidden after slice")
