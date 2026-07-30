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
	assert_true(chain_mechanic.is_enabled, "Mechanic should be enabled by default")

func test_chain_does_not_break_targets():
	grid_manager.target_solution[Vector3i(0, 0, 0)] = true
	grid_manager.on_chisel_requested(Vector3i(0, 1, 0)) # Chisel non-target, might trigger chain

	assert_true(grid_manager.blocks[Vector3i(0, 0, 0)].current_state == grid_manager.blocks[Vector3i(0,0,0)].BlockState.UNBROKEN, "Target block should remain unbroken")

func test_chain_breaks_zero_clue_lines():
	# Make all blocks non-targets
	grid_manager.target_solution.clear()

	# The line X=0, Y=0 (Z=0, Z=1) has no targets.
	# If we chisel (0,0,0), it should chain and break (0,0,1)
	grid_manager.on_chisel_requested(Vector3i(0, 0, 0))

	assert_true(grid_manager.blocks[Vector3i(0, 0, 1)].current_state == grid_manager.blocks[Vector3i(0,0,1)].BlockState.DESTROYED, "Chain should break the rest of the zero-clue line")

func test_undo_restores_chained_blocks():
	grid_manager.target_solution.clear()
	grid_manager.on_chisel_requested(Vector3i(0, 0, 0))

	assert_true(grid_manager.blocks[Vector3i(0, 0, 1)].current_state == grid_manager.blocks[Vector3i(0,0,1)].BlockState.DESTROYED, "Chain should break the block")

	grid_manager.undo_last_move()
	assert_true(grid_manager.blocks[Vector3i(0, 0, 1)].current_state == grid_manager.blocks[Vector3i(0,0,1)].BlockState.UNBROKEN, "Undo should restore chained blocks")
