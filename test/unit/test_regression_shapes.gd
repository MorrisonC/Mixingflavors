extends GutTest

const GridManagerClass = preload("res://scripts/GridManager.gd")
const GameManagerClass = preload("res://scripts/GameManager.gd")

var grid: GridManagerClass

func before_each():
	var gm = Node.new()
	gm.name = "GameManager"
	gm.set_script(GameManagerClass)
	get_tree().root.add_child(gm)

	grid = GridManagerClass.new()
	add_child_autoqfree(grid)

func after_each():
	var gm = get_tree().root.get_node_or_null("GameManager")
	if gm:
		gm.queue_free()

func test_solid_cube_fixture_win_and_near_miss():
	grid.grid_size = Vector3i(2, 2, 2)
	grid.is_puzzle_active = true
	grid.target_solution.clear()
	grid.voxel_states.clear()

	# 2x2x2 Solid Cube: All 8 voxels are target keepers
	for z in range(2):
		for y in range(2):
			for x in range(2):
				var pos = Vector3i(x, y, z)
				grid.target_solution[pos] = true
				grid.voxel_states[pos] = {
					"cell_state": GridManagerClass.CellState.UNBROKEN,
					"is_painted": false,
					"is_hidden_by_slice": false
				}

	# All target cells intact -> Win
	assert_true(grid.check_puzzle_complete(), "Solid 2x2x2 cube intact should return complete = true")

	# Near miss: Hammer 1 target cell -> False
	grid.hammer_cell(Vector3i(0, 0, 0))
	assert_false(grid.check_puzzle_complete(), "Solid cube with 1 hammered target cell should return complete = false")

func test_l_shape_fixture_win_and_near_miss():
	grid.grid_size = Vector3i(3, 3, 3)
	grid.is_puzzle_active = true
	grid.target_solution.clear()
	grid.voxel_states.clear()

	# L-Shape target voxels along X and Y axes
	var l_targets = [
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, 2, 0)
	]

	for z in range(3):
		for y in range(3):
			for x in range(3):
				var pos = Vector3i(x, y, z)
				var is_target = pos in l_targets
				grid.target_solution[pos] = is_target
				grid.voxel_states[pos] = {
					"cell_state": GridManagerClass.CellState.UNBROKEN,
					"is_painted": false,
					"is_hidden_by_slice": false
				}

	# Initially all unbroken -> False (since 22 non-target cells are unbroken)
	assert_false(grid.check_puzzle_complete(), "L-shape puzzle with unbroken non-targets should return complete = false")

	# Hammer 21 of the 22 non-target cells (Near miss: 1 non-target remaining)
	var non_targets = []
	for pos in grid.voxel_states.keys():
		if not grid.is_target_cell(pos):
			non_targets.append(pos)

	for i in range(non_targets.size() - 1):
		grid.hammer_cell(non_targets[i])

	assert_false(grid.check_puzzle_complete(), "L-shape puzzle with 1 remaining unbroken non-target cell should return complete = false")

	# Hammer the final 22nd non-target cell -> Win
	grid.hammer_cell(non_targets[-1])
	assert_true(grid.check_puzzle_complete(), "L-shape puzzle with all non-targets chiseled should return complete = true")

func test_plus_sign_fixture_win_and_near_miss():
	grid.grid_size = Vector3i(3, 3, 3)
	grid.is_puzzle_active = true
	grid.target_solution.clear()
	grid.voxel_states.clear()

	# 3D Plus Sign / Cross: Center core and 6 orthogonal arm points
	var plus_targets = [
		Vector3i(1, 1, 1),
		Vector3i(0, 1, 1), Vector3i(2, 1, 1),
		Vector3i(1, 0, 1), Vector3i(1, 2, 1),
		Vector3i(1, 1, 0), Vector3i(1, 1, 2)
	]

	for z in range(3):
		for y in range(3):
			for x in range(3):
				var pos = Vector3i(x, y, z)
				var is_target = pos in plus_targets
				grid.target_solution[pos] = is_target
				grid.voxel_states[pos] = {
					"cell_state": GridManagerClass.CellState.UNBROKEN,
					"is_painted": false,
					"is_hidden_by_slice": false
				}

	# Hammer all 20 non-target voxels
	for pos in grid.voxel_states.keys():
		if not grid.is_target_cell(pos):
			grid.hammer_cell(pos)

	# Mark a few target cells for player protection
	grid.mark_cell(Vector3i(1, 1, 1))
	grid.mark_cell(Vector3i(1, 2, 1))

	assert_true(grid.check_puzzle_complete(), "Plus-sign puzzle with all non-targets chiseled and optional marks should return complete = true")

	# Near miss: Accidentally hammer 1 of the target arm voxels -> False
	grid.hammer_cell(Vector3i(0, 1, 1))
	assert_false(grid.check_puzzle_complete(), "Plus-sign puzzle with 1 accidentally hammered target cell should return complete = false")
