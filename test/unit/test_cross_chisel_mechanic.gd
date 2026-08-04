extends GutTest

const GridManagerScene = preload("res://scenes/VoxelLogic.tscn")
var grid_manager
var cross_mechanic

func before_each():
	grid_manager = GridManagerScene.instantiate()
	grid_manager.base_grid_size = 3
	add_child(grid_manager)

	# Set puzzle as active so mechanics work
	grid_manager.set("is_puzzle_active", true)

	cross_mechanic = preload("res://scripts/CrossChiselMechanic.gd").new()
	cross_mechanic.name = "CrossChiselMechanic"
	cross_mechanic.combo_threshold = 5
	cross_mechanic.cross_radius = 1
	grid_manager.add_child(cross_mechanic)

	# Let nodes initialize
	await wait_frames(1)

func after_each():
	if is_instance_valid(grid_manager):
		grid_manager.queue_free()

func test_mechanic_initialization():
	assert_not_null(cross_mechanic, "CrossChiselMechanic should be created and added to tree")
	assert_true(cross_mechanic.is_enabled, "Mechanic should be enabled by default")

func test_cross_chisels_empty_blocks_on_threshold():
	# Make a 3x3 grid where ONLY (0, 0, 0) is a target to avoid chain reactions
	grid_manager.target_solution.clear()
	grid_manager.target_shape.clear()

	for pos in grid_manager.voxel_states.keys():
		grid_manager.voxel_states[pos] = {"is_target": false, "is_chiseled": false, "is_marked": false}

	# Put target far away so it's not chiseled
	var target_pos = Vector3i(0, 0, 0)
	grid_manager.voxel_states[target_pos]["is_target"] = true
	grid_manager.target_solution[target_pos] = true
	grid_manager.target_shape.append(target_pos)

	# Set combo to 4 (so the next chisel makes it 5)
	grid_manager.combo = 4

	# We chisel at (1, 1, 1). Adjacent are (2, 1, 1), (0, 1, 1), (1, 2, 1), (1, 0, 1), (1, 1, 2), (1, 1, 0)
	var chisel_pos = Vector3i(1, 1, 1)
	grid_manager.on_chisel_requested(chisel_pos)

	assert_eq(grid_manager.combo, 5, "Combo should be 5 after chiseling")

	# Check adjacent blocks are chiseled
	var adjacent_positions = [
		Vector3i(2, 1, 1), Vector3i(0, 1, 1),
		Vector3i(1, 2, 1), Vector3i(1, 0, 1),
		Vector3i(1, 1, 2), Vector3i(1, 1, 0)
	]

	for pos in adjacent_positions:
		assert_true(grid_manager.voxel_states[pos].get("is_chiseled", false), "Adjacent block at " + str(pos) + " should be chiseled by cross mechanic")

func test_cross_mechanic_ignores_targets():
	grid_manager.target_solution.clear()
	grid_manager.target_shape.clear()

	for pos in grid_manager.voxel_states.keys():
		grid_manager.voxel_states[pos] = {"is_target": false, "is_chiseled": false, "is_marked": false}

	# Set (2, 1, 1) as target
	var target_pos = Vector3i(2, 1, 1)
	grid_manager.voxel_states[target_pos]["is_target"] = true
	grid_manager.target_solution[target_pos] = true
	grid_manager.target_shape.append(target_pos)

	# Set combo to 4
	grid_manager.combo = 4

	var chisel_pos = Vector3i(1, 1, 1)
	grid_manager.on_chisel_requested(chisel_pos)

	# The target at (2, 1, 1) should NOT be chiseled
	assert_false(grid_manager.voxel_states[target_pos].get("is_chiseled", false), "Target block should NOT be chiseled by cross mechanic")

	# But another adjacent like (0, 1, 1) SHOULD be
	var empty_adj_pos = Vector3i(0, 1, 1)
	assert_true(grid_manager.voxel_states[empty_adj_pos].get("is_chiseled", false), "Empty adjacent block SHOULD be chiseled by cross mechanic")
