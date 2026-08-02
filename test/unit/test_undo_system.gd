extends GutTest

const GridManagerScene = preload("res://scenes/VoxelLogic.tscn")
var grid_manager

func before_each():
	grid_manager = GridManagerScene.instantiate()
	grid_manager.base_grid_size = 2
	add_child(grid_manager)

func after_each():
	grid_manager.queue_free()

func test_undo_multiple_moves():
	var pos1 = Vector3i(0, 0, 0)
	var pos2 = Vector3i(1, 0, 0)

	# Clear target solution to avoid mistake penalties during test
	grid_manager.target_solution = {}

	grid_manager.on_chisel_requested(pos1)
	assert_eq(grid_manager.blocks[pos1].current_state, 3, "Block 1 should be destroyed") # 3 = DESTROYED

	grid_manager.current_mode = grid_manager.EditMode.MARK
	grid_manager.on_mark_requested(pos2)
	assert_eq(grid_manager.blocks[pos2].current_state, 1, "Block 2 should be marked") # 1 = MARKED

	grid_manager.undo_last_move()
	assert_eq(grid_manager.blocks[pos2].current_state, 0, "Block 2 should be unbroken after undo") # 0 = UNBROKEN
	assert_eq(grid_manager.blocks[pos1].current_state, 3, "Block 1 should still be destroyed")

	grid_manager.undo_last_move()
	assert_eq(grid_manager.blocks[pos1].current_state, 0, "Block 1 should be unbroken after second undo")
