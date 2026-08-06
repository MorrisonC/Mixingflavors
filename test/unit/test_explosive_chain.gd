extends GutTest

const GridManagerClass = preload("res://scripts/GridManager.gd")
const ExplosiveChainMechanicClass = preload("res://scripts/ExplosiveChainMechanic.gd")

var grid_manager: GridManagerClass
var chain_mechanic: ExplosiveChainMechanicClass

func before_each():
	grid_manager = GridManagerClass.new()
	grid_manager.base_grid_size = 2
	add_child_autoqfree(grid_manager)

	grid_manager.start_level()

	chain_mechanic = ExplosiveChainMechanicClass.new()
	grid_manager.add_child(chain_mechanic)
	add_child_autoqfree(chain_mechanic)

func test_mechanic_disabled_by_default():
	assert_false(chain_mechanic.is_enabled, "Mechanic should be disabled by default")

func test_chain_does_not_break_targets():
	chain_mechanic.is_enabled = true
	grid_manager.target_solution[Vector3i(0, 0, 0)] = true
	grid_manager.target_shape.append(Vector3i(0, 0, 0))
	grid_manager.voxel_states[Vector3i(0, 0, 0)] = {"cell_state": GridManagerClass.CellState.UNBROKEN, "is_painted": false, "is_hidden_by_slice": false}
	grid_manager.on_chisel_requested(Vector3i(0, 1, 0)) # Chisel non-target, might trigger chain

	assert_false(grid_manager.is_cell_chiseled(Vector3i(0, 0, 0)), "Target block should remain unbroken")

func test_chain_breaks_zero_clue_lines():
	chain_mechanic.is_enabled = true
	# Make all blocks non-targets
	grid_manager.target_solution.clear()
	grid_manager.target_shape.clear()
	for pos in grid_manager.voxel_states.keys():
		grid_manager.voxel_states[pos] = {"cell_state": GridManagerClass.CellState.UNBROKEN, "is_painted": false, "is_hidden_by_slice": false}

	grid_manager.on_chisel_requested(Vector3i(0, 0, 0))

	assert_true(grid_manager.is_cell_chiseled(Vector3i(0, 0, 1)), "Chain should break the rest of the zero-clue line")

func test_undo_restores_chained_blocks():
	chain_mechanic.is_enabled = true
	grid_manager.target_solution.clear()
	grid_manager.target_shape.clear()
	for pos in grid_manager.voxel_states.keys():
		grid_manager.voxel_states[pos] = {"cell_state": GridManagerClass.CellState.UNBROKEN, "is_painted": false, "is_hidden_by_slice": false}

	grid_manager.on_chisel_requested(Vector3i(0, 0, 0))
	assert_true(grid_manager.is_cell_chiseled(Vector3i(0, 0, 1)), "Chain should break the block")

	grid_manager.undo_last_move()
	assert_false(grid_manager.is_cell_chiseled(Vector3i(0, 0, 1)), "Undo should restore chained blocks to unbroken state")