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

func test_explosive_chain_mechanic():
	# Clear target solution to ensure lines have 0 target blocks
	grid_manager.target_solution.clear()

	# Initial state: all unbroken (state 0)
	for pos in grid_manager.blocks:
		assert_eq(grid_manager.blocks[pos].current_state, 0, "Block should be initially unbroken")

	# Chisel block at (0, 0, 0)
	var start_pos = Vector3i(0, 0, 0)
	grid_manager.on_chisel_requested(start_pos)

	# Since there are no target blocks, lines from (0, 0, 0) should explode.
	# The grid is 2x2x2. Lines from (0,0,0) are X=(x,0,0), Y=(0,y,0), Z=(0,0,z).
	# So (1,0,0), (0,1,0), and (0,0,1) should also be destroyed (state 3)

	assert_eq(grid_manager.blocks[start_pos].current_state, 3, "Start block should be destroyed")
	assert_eq(grid_manager.blocks[Vector3i(1, 0, 0)].current_state, 3, "Block (1,0,0) should explode")
	assert_eq(grid_manager.blocks[Vector3i(0, 1, 0)].current_state, 3, "Block (0,1,0) should explode")
	assert_eq(grid_manager.blocks[Vector3i(0, 0, 1)].current_state, 3, "Block (0,0,1) should explode")

	# Blocks not on those axes should NOT explode
	assert_eq(grid_manager.blocks[Vector3i(1, 1, 1)].current_state, 0, "Block (1,1,1) should remain unbroken")
