extends GutTest

const GridManagerScene = preload("res://scenes/VoxelLogic.tscn")
var grid_manager

func before_each():
	var gm = get_tree().root.get_node_or_null("GameManager")
	if not gm:
		gm = Node.new()
		gm.name = "GameManager"
		get_tree().root.add_child(gm)

	grid_manager = GridManagerScene.instantiate()
	grid_manager.set("base_grid_size", 2)
	add_child(grid_manager)

func after_each():
	grid_manager.queue_free()
	var gm = get_tree().root.get_node_or_null("GameManager")
	if gm:
		gm.queue_free()

func test_undo_multiple_moves():
	var pos1 = Vector3i(0, 0, 0)
	var pos2 = Vector3i(1, 0, 0)

	# Force start the level to ensure puzzle is active
	grid_manager._build_grid()
	grid_manager.is_puzzle_active = true
	grid_manager.target_solution.clear()
	grid_manager.voxel_states.clear()

	for pos in grid_manager.blocks:
		grid_manager.voxel_states[pos] = {"is_target": false, "is_chiseled": false, "is_marked": false}
		grid_manager.blocks[pos].set_state(0)

	var chain = grid_manager.get_node_or_null("ExplosiveChainMechanic")
	if chain:
		chain.is_enabled = false

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
