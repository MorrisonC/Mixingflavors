extends GutTest

const GridManagerScene = preload("res://scenes/Picross3D.tscn")
var grid_manager: Node = null
var explosive_mechanic: Node = null

func before_each() -> void:
	grid_manager = GridManagerScene.instantiate()
	grid_manager.grid_size = Vector3i(3, 3, 3)

	# Setting base grid size to prevent Game Over issues
	grid_manager.base_grid_size = 3

	# The explosive mechanic is now a child in the scene
	explosive_mechanic = grid_manager.get_node("ExplosiveChainMechanic")

	add_child(grid_manager)

func after_each() -> void:
	if is_instance_valid(grid_manager):
		grid_manager.queue_free()

func test_explosive_chain_reaction_active() -> void:
	explosive_mechanic.is_active = true
	explosive_mechanic.blast_radius = 1

	var center_pos = Vector3i(1, 1, 1)

	# Trigger player action on center block
	grid_manager.on_chisel_requested(center_pos, true)

	# Verify the center block is destroyed
	assert_eq(grid_manager.blocks[center_pos].current_state, 2, "Center block should be destroyed") # 2 = DESTROYED

	# Verify adjacent blocks are destroyed
	var adj1 = Vector3i(2, 1, 1)
	var adj2 = Vector3i(0, 1, 1)
	var adj3 = Vector3i(1, 2, 1)
	var adj4 = Vector3i(1, 0, 1)
	var adj5 = Vector3i(1, 1, 2)
	var adj6 = Vector3i(1, 1, 0)

	assert_eq(grid_manager.blocks[adj1].current_state, 2, "Adjacent block +X should be destroyed")
	assert_eq(grid_manager.blocks[adj2].current_state, 2, "Adjacent block -X should be destroyed")
	assert_eq(grid_manager.blocks[adj3].current_state, 2, "Adjacent block +Y should be destroyed")
	assert_eq(grid_manager.blocks[adj4].current_state, 2, "Adjacent block -Y should be destroyed")
	assert_eq(grid_manager.blocks[adj5].current_state, 2, "Adjacent block +Z should be destroyed")
	assert_eq(grid_manager.blocks[adj6].current_state, 2, "Adjacent block -Z should be destroyed")

	# Verify diagonal block is NOT destroyed (radius = 1)
	var diag_pos = Vector3i(2, 2, 1)
	assert_eq(grid_manager.blocks[diag_pos].current_state, 0, "Diagonal block should NOT be destroyed") # 0 = UNBROKEN

func test_explosive_chain_reaction_inactive() -> void:
	explosive_mechanic.is_active = false
	explosive_mechanic.blast_radius = 1

	var center_pos = Vector3i(1, 1, 1)
	grid_manager.on_chisel_requested(center_pos, true)

	# Verify the center block is destroyed
	assert_eq(grid_manager.blocks[center_pos].current_state, 2, "Center block should be destroyed")

	# Verify adjacent block is NOT destroyed since mechanic is inactive
	var adj1 = Vector3i(2, 1, 1)
	assert_eq(grid_manager.blocks[adj1].current_state, 0, "Adjacent block +X should NOT be destroyed")

func test_undo_explosive_chain_reaction() -> void:
	explosive_mechanic.is_active = true
	explosive_mechanic.blast_radius = 1

	var center_pos = Vector3i(1, 1, 1)
	var adj1 = Vector3i(2, 1, 1)

	grid_manager.on_chisel_requested(center_pos, true)

	assert_eq(grid_manager.blocks[center_pos].current_state, 2, "Center block destroyed")
	assert_eq(grid_manager.blocks[adj1].current_state, 2, "Adjacent block destroyed")

	# Now perform undo
	grid_manager.undo_last_move()

	# Verify both are reverted back to UNBROKEN
	assert_eq(grid_manager.blocks[center_pos].current_state, 0, "Center block should be unbroken")
	assert_eq(grid_manager.blocks[adj1].current_state, 0, "Adjacent block should be unbroken")

func test_combo_not_incremented_multiple_times() -> void:
	explosive_mechanic.is_active = true
	explosive_mechanic.blast_radius = 1

	var initial_combo = grid_manager.combo
	var center_pos = Vector3i(1, 1, 1)

	# Ensure it's not a target block to avoid combo reset (by default target_solution sets edges false, core true)
	# (1,1,1) is true (filled) by default in _generate_solution. Let's pick a non-target so combo goes up.
	# Wait, if (1,1,1) is a target, chiseling it is a mistake.
	# Let's chisel (0, 0, 0) instead.
	var corner_pos = Vector3i(0, 0, 0)

	grid_manager.on_chisel_requested(corner_pos, true)

	# Corner is not a target. It gets destroyed (player action).
	# Adjacents (1,0,0), (0,1,0), (0,0,1) get destroyed (non-player action).

	assert_eq(grid_manager.combo, initial_combo + 1, "Combo should only increment once for the player action")
