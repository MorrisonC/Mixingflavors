extends GutTest

const GridManagerClass = preload("res://scripts/GridManager.gd")
const BlockClass = preload("res://scripts/Block.gd")
const GameManagerClass = preload("res://scripts/GameManager.gd")

var grid: GridManagerClass
var _created_game_manager: bool = false

func before_each() -> void:
	_created_game_manager = false
	if not get_tree().root.has_node("GameManager"):
		var game_manager := Node.new()
		game_manager.name = "GameManager"
		game_manager.set_script(GameManagerClass)
		get_tree().root.add_child(game_manager)
		_created_game_manager = true
	grid = GridManagerClass.new()
	grid.base_grid_size = 3
	add_child_autoqfree(grid)

func after_each() -> void:
	if _created_game_manager:
		var game_manager := get_tree().root.get_node_or_null("GameManager")
		if game_manager:
			game_manager.queue_free()

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
	# Two ordered groups of target blocks -> "1·2"
	grid.grid_size = Vector3i(5, 1, 1)
	grid.target_solution = {
		Vector3i(0, 0, 0): true,
		Vector3i(3, 0, 0): true,
		Vector3i(4, 0, 0): true
	}
	var clue = grid._calculate_clue(Vector3i(0, 0, 0), Vector3i(1, 0, 0), 5)
	assert_eq(clue, [1, 2], "Two groups (len 1 and len 2) should return [1, 2]")
	var formatted = grid._format_hint_text(clue)
	assert_eq(formatted, "1·2", "Formatted text must preserve the order of two groups")

func test_calculate_clues_square_group():
	# Three ordered groups of target blocks -> "1·1·1"
	grid.grid_size = Vector3i(5, 1, 1)
	grid.target_solution = {
		Vector3i(0, 0, 0): true,
		Vector3i(2, 0, 0): true,
		Vector3i(4, 0, 0): true
	}
	var clue = grid._calculate_clue(Vector3i(0, 0, 0), Vector3i(1, 0, 0), 5)
	assert_eq(clue, [1, 1, 1], "Three groups should return [1, 1, 1]")
	var formatted = grid._format_hint_text(clue)
	assert_eq(formatted, "1·1·1", "Formatted text must preserve the order of three groups")

func test_marked_blocks_remain_valid_clue_hosts():
	grid.start_level()
	var test_pos := Vector3i(0, 0, 0)
	assert_true(grid.mark_cell(test_pos))
	grid._update_clues()
	var block := grid.blocks[test_pos] as VoxelBlock
	var visible_hint_count: int = 0
	for direction: Vector3i in block.face_labels.keys():
		if (block.face_labels[direction] as Label3D).visible:
			visible_hint_count += 1
	assert_gt(visible_hint_count, 0, "Marked visible cells must continue hosting line clues")
