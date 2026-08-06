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
	grid.base_grid_size = 2
	add_child_autoqfree(grid)

func after_each():
	var gm = get_tree().root.get_node_or_null("GameManager")
	if gm:
		gm.queue_free()

func test_chisel_non_target_destroys_block():
	grid.start_level()
	var test_pos = Vector3i(0, 0, 0)
	grid.target_solution[test_pos] = false

	grid.on_chisel_requested(test_pos)

	assert_true(grid.is_cell_chiseled(test_pos), "Non-target block should be chiseled")
	assert_eq(grid.blocks[test_pos].current_state, BlockClass.BlockState.DESTROYED, "Block state should be DESTROYED")

func test_chisel_target_triggers_mistake_and_marks():
	grid.start_level()
	var test_pos = Vector3i(0, 0, 0)
	grid.target_solution[test_pos] = true
	var initial_hp = grid.player_hp

	grid.on_chisel_requested(test_pos)

	assert_eq(grid.player_hp, initial_hp - 1, "Chiseling target block should cost 1 HP")
	assert_true(grid.is_cell_marked(test_pos), "Chiseling target block should mark it to preserve puzzle structure")
	assert_eq(grid.blocks[test_pos].current_state, BlockClass.BlockState.MARKED, "Block state should be MARKED")

func test_mark_toggle_unbroken_and_marked():
	grid.start_level()
	grid.current_mode = grid.EditMode.MARK
	var test_pos = Vector3i(0, 0, 0)

	grid.on_mark_requested(test_pos)
	assert_true(grid.is_cell_marked(test_pos), "Marking unbroken block should mark it")
	assert_eq(grid.blocks[test_pos].current_state, BlockClass.BlockState.MARKED, "Block state should be MARKED")

	grid.on_mark_requested(test_pos)
	assert_false(grid.is_cell_marked(test_pos), "Marking already marked block should unmark it")
	assert_eq(grid.blocks[test_pos].current_state, BlockClass.BlockState.UNBROKEN, "Block state should return to UNBROKEN")

func test_slicing_hides_outer_blocks():
	grid.start_level()
	var inside_pos = Vector3i(0, 0, 0)
	var outside_pos = Vector3i(1, 1, 1)

	grid.slice_max = Vector3i(0, 0, 0)
	grid._update_slicing()

	assert_false(grid.voxel_states[inside_pos].get("is_hidden_by_slice", false), "Inside slice bounds block should remain visible")
	assert_true(grid.voxel_states[outside_pos].get("is_hidden_by_slice", false), "Outside slice bounds block should be hidden by slice")
