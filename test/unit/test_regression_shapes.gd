extends GutTest

const VoxelBlockClass = preload("res://scripts/Block.gd")

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

	# A kept voxel must not be destroyable through the state primitive at all.
	# That is now the stronger guarantee, so assert it directly.
	assert_false(grid.hammer_cell(Vector3i(0, 0, 0)), "the primitive must refuse to destroy a kept voxel")
	assert_true(grid.check_puzzle_complete(), "A refused chisel must leave a solved cube solved")

	# And the win condition must still reject a destroyed target if state is ever
	# corrupted from outside (a migration, a bad save, a future mechanic).
	grid.voxel_states[Vector3i(0, 0, 0)]["cell_state"] = GridManagerClass.CellState.DESTROYED
	assert_false(grid.check_puzzle_complete(), "Solid cube with 1 destroyed target cell should return complete = false")

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

	# Near miss: a kept voxel cannot be chiselled at all, so the round stays won.
	assert_false(grid.hammer_cell(Vector3i(0, 1, 1)), "the primitive must refuse to destroy a kept voxel")
	assert_true(grid.check_puzzle_complete(), "A refused chisel must leave a solved puzzle solved")
	# If state is ever corrupted from outside, the win condition must still reject it.
	grid.voxel_states[Vector3i(0, 1, 1)]["cell_state"] = GridManagerClass.CellState.DESTROYED
	assert_false(grid.check_puzzle_complete(), "Plus-sign puzzle with 1 destroyed target cell should return complete = false")

# Grouped clues are joined with the "·" display separator, e.g. "1·2". A plain
# to_int() on that string yields 0, which rendered the clue as the red "unknown"
# marker and hid the kind sprite. The groups must be summed instead.
func test_grouped_clue_totals_are_summed_not_parsed_as_zero() -> void:
	var block: VoxelBlock = VoxelBlockClass.new()
	block.lightweight_mode = true
	add_child_autoqfree(block)
	var direction := Vector3i(0, 1, 0)
	block.set_face_hint(direction, "(1·2)")
	var label: Label3D = block.face_labels[direction] as Label3D
	assert_not_null(label, "clue host should lazily create its face label")
	assert_eq(label.text, "1·2", "grouped clue text should stay grouped for readability")
	assert_ne(label.modulate, Color("#ff6b7a"), "a valid grouped clue must not render as the red unknown marker")
	assert_true(block.face_sprites[direction].visible, "parenthesised group should show its circle marker")

func test_grouped_clue_of_three_groups_sums_correctly() -> void:
	var block: VoxelBlock = VoxelBlockClass.new()
	block.lightweight_mode = true
	add_child_autoqfree(block)
	var direction := Vector3i(1, 0, 0)
	block.set_face_hint(direction, "[2·3·1]")
	var label: Label3D = block.face_labels[direction] as Label3D
	assert_eq(label.text, "2·3·1")
	assert_ne(label.modulate, Color("#ff6b7a"), "three-group clue must not render as unknown")
	assert_true(block.face_sprites[direction].visible, "bracketed group should show its square marker")

func test_single_group_clue_still_behaves() -> void:
	var block: VoxelBlock = VoxelBlockClass.new()
	block.lightweight_mode = true
	add_child_autoqfree(block)
	var direction := Vector3i(0, 0, 1)
	block.set_face_hint(direction, "(3)")
	var label: Label3D = block.face_labels[direction] as Label3D
	assert_eq(label.text, "3")
	assert_ne(label.modulate, Color("#ff6b7a"))
	assert_true(block.face_sprites[direction].visible)
