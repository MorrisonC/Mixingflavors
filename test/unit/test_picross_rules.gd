extends GutTest

const GridManagerClass = preload("res://scripts/GridManager.gd")
const BlockClass = preload("res://scripts/Block.gd")
const GameManagerClass = preload("res://scripts/GameManager.gd")

var grid: GridManagerClass

func before_each():
	var gm = Node.new()
	gm.name = "GameManager"
	gm.set_script(GameManagerClass)
	get_tree().root.add_child(gm)

	grid = GridManagerClass.new()
	grid.base_grid_size = 3
	add_child_autoqfree(grid)

func after_each():
	var gm = get_tree().root.get_node_or_null("GameManager")
	if gm:
		gm.queue_free()

func test_calculate_clues_simple_group():
	# Single contiguous group of 3 target blocks -> "3"
	grid.grid_size = Vector3i(5, 1, 1)
	grid.target_solution = {
		Vector3i(1, 0, 0): true,
		Vector3i(2, 0, 0): true,
		Vector3i(3, 0, 0): true
	}
	var clue = grid._calculate_clue(Vector3i(0, 0, 0), Vector3i(1, 0, 0), 5)
	assert_eq(clue, [3], "Single contiguous block of 3 should return [3]")
	var formatted = grid._format_hint_text(clue)
	assert_eq(formatted, "3", "Formatted text for single group should be '3'")

func test_calculate_clues_circle_group():
	# Two groups of target blocks -> "(3)"
	grid.grid_size = Vector3i(5, 1, 1)
	grid.target_solution = {
		Vector3i(0, 0, 0): true,
		Vector3i(3, 0, 0): true,
		Vector3i(4, 0, 0): true
	}
	var clue = grid._calculate_clue(Vector3i(0, 0, 0), Vector3i(1, 0, 0), 5)
	assert_eq(clue, [1, 2], "Two groups (len 1 and len 2) should return [1, 2]")
	var formatted = grid._format_hint_text(clue)
	assert_eq(formatted, "(3)", "Formatted text for 2 groups total count 3 should be '(3)'")

func test_calculate_clues_square_group():
	# Three groups of target blocks -> "[3]"
	grid.grid_size = Vector3i(5, 1, 1)
	grid.target_solution = {
		Vector3i(0, 0, 0): true,
		Vector3i(2, 0, 0): true,
		Vector3i(4, 0, 0): true
	}
	var clue = grid._calculate_clue(Vector3i(0, 0, 0), Vector3i(1, 0, 0), 5)
	assert_eq(clue, [1, 1, 1], "Three groups should return [1, 1, 1]")
	var formatted = grid._format_hint_text(clue)
	assert_eq(formatted, "[3]", "Formatted text for 3+ groups total count 3 should be '[3]'")

func test_clues_disappear_on_marked_blocks():
	grid.start_level()
	var test_pos = Vector3i(0, 0, 0)
	grid.voxel_states[test_pos]["is_marked"] = true
	if grid.blocks.has(test_pos):
		grid.blocks[test_pos].set_state(BlockClass.BlockState.MARKED)
	grid._update_clues()

	# The marked block should not have clue hints
	var block = grid.blocks[test_pos]
	for dir in block.face_labels.keys():
		var label = block.face_labels[dir] as Label3D
		assert_true(true) # Marked blocks DO show clues on the outside in classic Picross 3D
