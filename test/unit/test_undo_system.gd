extends GutTest

const GridManagerScene: PackedScene = preload("res://scenes/VoxelLogic.tscn")

var grid_manager: GridManager

func before_each() -> void:
	grid_manager = GridManagerScene.instantiate()
	grid_manager.base_grid_size = 2
	add_child_autoqfree(grid_manager)
	grid_manager.is_puzzle_active = true
	grid_manager.input_locked = false
	grid_manager.puzzle_solved_emitted = false
	grid_manager.target_shape.clear()
	for pos: Vector3i in grid_manager.voxel_states.keys():
		grid_manager.target_solution[pos] = false
		grid_manager.voxel_states[pos]["is_target"] = false
		grid_manager.voxel_states[pos]["cell_state"] = GridManager.CellState.UNBROKEN
	grid_manager.move_history.clear()
	grid_manager._update_clues()

func test_undo_multiple_moves() -> void:
	var first_pos := Vector3i(0, 0, 0)
	var second_pos := Vector3i(1, 0, 0)
	grid_manager.on_chisel_requested(first_pos)
	assert_eq(grid_manager.blocks[first_pos].current_state, VoxelBlock.BlockState.DESTROYED)
	grid_manager.current_mode = GridManager.EditMode.MARK
	grid_manager.on_mark_requested(second_pos)
	assert_eq(grid_manager.blocks[second_pos].current_state, VoxelBlock.BlockState.MARKED)
	grid_manager.undo_last_move()
	assert_eq(grid_manager.blocks[second_pos].current_state, VoxelBlock.BlockState.UNBROKEN)
	assert_eq(grid_manager.blocks[first_pos].current_state, VoxelBlock.BlockState.DESTROYED)
	grid_manager.undo_last_move()
	assert_eq(grid_manager.blocks[first_pos].current_state, VoxelBlock.BlockState.UNBROKEN)

func test_undo_restores_editor_target_change() -> void:
	grid_manager.is_editor_mode = true
	var pos := Vector3i(0, 0, 0)
	grid_manager._set_editor_target(pos, true)
	assert_true(grid_manager.is_target_cell(pos))
	grid_manager.undo_last_move()
	assert_false(grid_manager.is_target_cell(pos))
	assert_true(grid_manager.is_cell_unbroken(pos))
