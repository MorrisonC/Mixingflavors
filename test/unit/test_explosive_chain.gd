extends GutTest

const GridManagerScene = preload("res://scenes/VoxelLogic.tscn")
var grid_manager
var chain_mechanic

func before_each():
	grid_manager = GridManagerScene.instantiate()
	grid_manager.base_grid_size = 2
	add_child(grid_manager)

	# Mechanic is a child of GridManager in the updated scene
	chain_mechanic = grid_manager.get_node_or_null("ExplosiveChainMechanic")

func after_each():
	grid_manager.queue_free()

func test_mechanic_initialization():
	assert_not_null(chain_mechanic, "ExplosiveChainMechanic node should be instantiated")
	assert_false(chain_mechanic.is_enabled, "Mechanic should be disabled by default")

func test_chain_does_not_break_targets():
	chain_mechanic.is_enabled = true
	grid_manager.target_solution[Vector3i(0, 0, 0)] = true
	grid_manager.target_shape.append(Vector3i(0, 0, 0))
	grid_manager.voxel_states[Vector3i(0, 0, 0)] = {"is_target": true, "is_chiseled": false, "is_marked": false}
	grid_manager.on_chisel_requested(Vector3i(0, 1, 0)) # Chisel non-target, might trigger chain

	assert_false(grid_manager.voxel_states[Vector3i(0, 0, 0)].get("is_chiseled", false), "Target block should remain unbroken")

func test_chain_breaks_zero_clue_lines():
	chain_mechanic.is_enabled = true
	# Make all blocks non-targets
	grid_manager.target_solution.clear()
	grid_manager.target_shape.clear()
	for pos in grid_manager.voxel_states.keys():
		grid_manager.voxel_states[pos] = {"is_target": false, "is_chiseled": false, "is_marked": false}

	grid_manager.on_chisel_requested(Vector3i(0, 0, 0))

	assert_true(grid_manager.voxel_states[Vector3i(0, 0, 1)].get("is_chiseled", false), "Chain should break the rest of the zero-clue line")

func test_undo_restores_chained_blocks():
	chain_mechanic.is_enabled = true
	grid_manager.target_solution.clear()
	grid_manager.target_shape.clear()
	for pos in grid_manager.voxel_states.keys():
		grid_manager.voxel_states[pos] = {"is_target": false, "is_chiseled": false, "is_marked": false}

	grid_manager.on_chisel_requested(Vector3i(0, 0, 0))

	assert_true(grid_manager.voxel_states[Vector3i(0, 0, 1)].get("is_chiseled", false), "Chain should break the block")

	grid_manager.undo_last_move()
	assert_false(grid_manager.voxel_states[Vector3i(0, 0, 1)].get("is_chiseled", false), "Undo should restore chained blocks")