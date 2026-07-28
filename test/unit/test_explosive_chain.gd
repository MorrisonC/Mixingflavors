extends GutTest

const GridManagerScene = preload("res://scenes/Picross3D.tscn")
var grid_manager

func before_each():
	grid_manager = GridManagerScene.instantiate()
	grid_manager.base_grid_size = 3
	add_child(grid_manager)

func after_each():
	grid_manager.queue_free()

func test_explosive_chain_mechanic():
	# Force some setup
	grid_manager.grid_size = Vector3i(3, 3, 3)
	grid_manager._generate_solution()
	grid_manager._build_grid()

	# Let's say solution is true for (1,1,1)
	assert_true(grid_manager.target_solution.get(Vector3i(1,1,1), false))

	# Ensure combo is 4
	grid_manager.combo = 4

	# Chisel a non-target block at (0,0,0)
	var start_pos = Vector3i(0,0,0)
	grid_manager.on_chisel_requested(start_pos)

	# Combo should be 5, triggering explosive chain
	assert_eq(grid_manager.combo, 5, "Combo should increment to 5")

	# The explosive chain should automatically chisel adjacent blocks
	# Adjacents to (0,0,0) are (1,0,0), (0,1,0), (0,0,1).
	# They are non-target blocks, so they should be destroyed.
	var block_x = grid_manager.blocks[Vector3i(1,0,0)]
	var block_y = grid_manager.blocks[Vector3i(0,1,0)]
	var block_z = grid_manager.blocks[Vector3i(0,0,1)]

	assert_eq(block_x.current_state, block_x.BlockState.DESTROYED, "Adjacent block X should be destroyed by chain")
	assert_eq(block_y.current_state, block_y.BlockState.DESTROYED, "Adjacent block Y should be destroyed by chain")
	assert_eq(block_z.current_state, block_z.BlockState.DESTROYED, "Adjacent block Z should be destroyed by chain")

	# Combo should remain 5 because automated chain shouldn't increase it
	assert_eq(grid_manager.combo, 5, "Combo should not increase from automated chain")
