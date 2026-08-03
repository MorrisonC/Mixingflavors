extends GutTest

const GridManagerScene = preload("res://scenes/VoxelLogic.tscn")
var grid_manager
var crystal_mechanic

func before_each():
	grid_manager = GridManagerScene.instantiate()
	grid_manager.base_grid_size = 2
	# Need to fake that puzzle is active for process checks to pass
	grid_manager.set("is_puzzle_active", true)
	add_child(grid_manager)

	# Wait a frame to let children initialize and ready
	await wait_frames(1)

	crystal_mechanic = grid_manager.get_node_or_null("BonusCrystalMechanic")

func after_each():
	if is_instance_valid(grid_manager):
		grid_manager.queue_free()

func test_mechanic_initialization():
	assert_not_null(crystal_mechanic, "BonusCrystalMechanic node should be instantiated")
	assert_true(crystal_mechanic.is_enabled, "Mechanic should be enabled by default")

func test_crystal_spawns_on_unbroken_block():
	# Make all blocks non-targets so they are valid spawn locations
	grid_manager.target_solution.clear()
	grid_manager.target_shape.clear()
	for pos in grid_manager.voxel_states.keys():
		grid_manager.voxel_states[pos] = {"is_target": false, "is_chiseled": false, "is_marked": false}

	# Force a spawn
	crystal_mechanic._spawn_crystal()

	assert_ne(crystal_mechanic.active_crystal_pos, Vector3i(-1, -1, -1), "Crystal should spawn on a valid position")
	var block = grid_manager.blocks[crystal_mechanic.active_crystal_pos]
	assert_eq(block.current_state, block.BlockState.UNBROKEN, "Crystal should spawn on an unbroken block")

func test_crystal_destruction_gives_bonus():
	grid_manager.target_solution.clear()
	grid_manager.target_shape.clear()
	for pos in grid_manager.voxel_states.keys():
		grid_manager.voxel_states[pos] = {"is_target": false, "is_chiseled": false, "is_marked": false}

	# Manually set a combo
	grid_manager.combo = 2

	# Force a spawn
	crystal_mechanic._spawn_crystal()
	var pos = crystal_mechanic.active_crystal_pos

	assert_ne(pos, Vector3i(-1, -1, -1), "Crystal should spawn")

	# Simulate player destroying the block
	grid_manager.on_chisel_requested(pos)

	# Destroying a block increments combo by 1 in GridManager natively, plus our bonus (5 by default)
	# So 2 + 1 + 5 = 8
	var expected_combo = 2 + 1 + crystal_mechanic.bonus_combo
	assert_eq(grid_manager.combo, expected_combo, "Combo should increase by base + bonus amount")
	assert_eq(crystal_mechanic.active_crystal_pos, Vector3i(-1, -1, -1), "Crystal should reset after being destroyed")

func test_mechanic_disabled_when_flag_false():
	crystal_mechanic.is_enabled = false
	crystal_mechanic.spawn_timer = 999.0 # Past interval

	crystal_mechanic._process(0.1)

	assert_eq(crystal_mechanic.active_crystal_pos, Vector3i(-1, -1, -1), "Crystal should not spawn if mechanic is disabled")
