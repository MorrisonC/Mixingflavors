extends GutTest

const GridManagerScene: PackedScene = preload("res://scenes/VoxelLogic.tscn")
const BlockScene: PackedScene = preload("res://scenes/Block.tscn")

var grid_manager: GridManager

func before_each() -> void:
	var game_manager := get_tree().root.get_node_or_null("GameManager")
	if game_manager:
		game_manager.set("mode_payload", {})
	grid_manager = GridManagerScene.instantiate()
	grid_manager.base_grid_size = 2
	add_child_autoqfree(grid_manager)

func test_build_grid_uses_only_in_bounds_state() -> void:
	assert_eq(grid_manager.grid_size, Vector3i(2, 2, 2))
	assert_eq(grid_manager.blocks.size(), 8)
	assert_eq(grid_manager.voxel_states.size(), 8)
	assert_eq(grid_manager.target_solution.size(), 8)

func test_slicing_preserves_canonical_mark_state() -> void:
	var pos := Vector3i(1, 1, 1)
	assert_true(grid_manager.mark_cell(pos))
	grid_manager.slice_max = Vector3i(0, 0, 0)
	grid_manager._update_slicing()
	assert_true(grid_manager.voxel_states[pos]["is_hidden_by_slice"])
	assert_eq(grid_manager.blocks[pos].current_state, VoxelBlock.BlockState.HIDDEN_BY_SLICE)
	grid_manager.slice_max = Vector3i(1, 1, 1)
	grid_manager._update_slicing()
	assert_true(grid_manager.is_cell_marked(pos))
	assert_eq(grid_manager.blocks[pos].current_state, VoxelBlock.BlockState.MARKED)

func test_zero_and_grouped_clues_are_renderable() -> void:
	assert_eq(grid_manager._format_hint_text([]), "0")
	assert_eq(grid_manager._format_hint_text([3]), "3")
	assert_eq(grid_manager._format_hint_text([1, 2]), "(3)")
	assert_eq(grid_manager._format_hint_text([1, 1, 1]), "[3]")
	var block := BlockScene.instantiate() as VoxelBlock
	add_child_autoqfree(block)
	await get_tree().process_frame
	block.set_face_hint(Vector3i(1, 0, 0), "0")
	assert_true((block.face_labels[Vector3i(1, 0, 0)] as Label3D).visible)
	assert_eq((block.face_labels[Vector3i(1, 0, 0)] as Label3D).text, "0")

func test_is_cell_correct_logic() -> void:
	var target_pos := Vector3i(0, 0, 0)
	var non_target_pos := Vector3i(1, 1, 1)
	grid_manager.target_solution[target_pos] = true
	grid_manager.target_solution[non_target_pos] = false
	grid_manager.voxel_states[target_pos]["is_target"] = true
	grid_manager.voxel_states[non_target_pos]["is_target"] = false
	assert_true(grid_manager.is_cell_correct(target_pos))
	assert_false(grid_manager.is_cell_correct(non_target_pos))
	assert_true(grid_manager.hammer_cell(non_target_pos))
	assert_true(grid_manager.is_cell_correct(non_target_pos))
	assert_true(grid_manager.hammer_cell(target_pos))
	assert_false(grid_manager.is_cell_correct(target_pos))

func test_preassigned_custom_puzzle_is_loaded_once() -> void:
	var custom_grid := GridManagerScene.instantiate()
	custom_grid.custom_puzzle_data = {
		"id": "unit_custom",
		"dims": [2, 1, 1],
		"target_voxels": [[1, 0, 0]],
		"name": "Unit Custom"
	}
	add_child_autoqfree(custom_grid)
	assert_true(custom_grid.has_custom_puzzle)
	assert_eq(custom_grid.grid_size, Vector3i(2, 1, 1))
	assert_true(custom_grid.is_target_cell(Vector3i(1, 0, 0)))
	assert_false(custom_grid.is_target_cell(Vector3i(0, 0, 0)))
	assert_eq(custom_grid.blocks.size(), 2)

func test_puzzle_solved_emits_only_once_and_locks_input() -> void:
	for pos: Vector3i in grid_manager.voxel_states.keys():
		grid_manager.target_solution[pos] = true
		grid_manager.voxel_states[pos]["is_target"] = true
		grid_manager.voxel_states[pos]["cell_state"] = GridManager.CellState.UNBROKEN
	var solve_count: Array[int] = [0]
	grid_manager.puzzle_solved.connect(func() -> void: solve_count[0] += 1)
	grid_manager._check_win_condition()
	grid_manager._check_win_condition()
	assert_eq(solve_count[0], 1)
	assert_false(grid_manager.is_puzzle_active)
	assert_true(grid_manager.input_locked)
