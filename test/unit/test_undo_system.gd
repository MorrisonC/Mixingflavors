extends GutTest

const GridManagerScene: PackedScene = preload("res://scenes/VoxelLogic.tscn")

var grid_manager: GridManager

func before_each() -> void:
	grid_manager = GridManagerScene.instantiate()
	grid_manager.base_grid_size = 2
	add_child_autoqfree(grid_manager)
	grid_manager.is_puzzle_active = true
	grid_manager.input_locked = false
	grid_manager.puzzle_solved_emitted = false
	grid_manager.target_shape.clear()
	for pos: Vector3i in grid_manager.voxel_states.keys():
		grid_manager.target_solution[pos] = false
		grid_manager.voxel_states[pos]["is_target"] = false
		grid_manager.voxel_states[pos]["cell_state"] = GridManager.CellState.UNBROKEN
	grid_manager.move_history.clear()
	grid_manager._update_clues()

func test_undo_multiple_moves() -> void:
	var first_pos := Vector3i(0, 0, 0)
	var second_pos := Vector3i(1, 0, 0)
	grid_manager.on_chisel_requested(first_pos)
	assert_eq(grid_manager.blocks[first_pos].current_state, VoxelBlock.BlockState.DESTROYED)
	grid_manager.current_mode = GridManager.EditMode.MARK
	grid_manager.on_mark_requested(second_pos)
	assert_eq(grid_manager.blocks[second_pos].current_state, VoxelBlock.BlockState.MARKED)
	grid_manager.undo_last_move()
	assert_eq(grid_manager.blocks[second_pos].current_state, VoxelBlock.BlockState.UNBROKEN)
	assert_eq(grid_manager.blocks[first_pos].current_state, VoxelBlock.BlockState.DESTROYED)
	grid_manager.undo_last_move()
	assert_eq(grid_manager.blocks[first_pos].current_state, VoxelBlock.BlockState.UNBROKEN)

func test_undo_restores_editor_target_change() -> void:
	grid_manager.is_editor_mode = true
	var pos := Vector3i(0, 0, 0)
	grid_manager._set_editor_target(pos, true)
	assert_true(grid_manager.is_target_cell(pos))
	grid_manager.undo_last_move()
	assert_false(grid_manager.is_target_cell(pos))
	assert_true(grid_manager.is_cell_unbroken(pos))


# Undo restored the cells but not the combo. Combo is the trigger for the
# combo-heal mistake refund and it feeds the score bonus, so re-chiselling the
# same voxels after an undo inflated the combo without any new information and
# laundered the run's mistake budget.
func test_undo_restores_the_combo_so_rechisel_cannot_inflate_it() -> void:
	var first := Vector3i(0, 0, 0)
	var second := Vector3i(1, 0, 0)
	grid_manager.on_chisel_requested(first)
	grid_manager.on_chisel_requested(second)
	var earned: int = grid_manager.combo
	assert_eq(earned, 2, "two correct chisels should build a combo of two")
	grid_manager.undo_last_move()
	assert_eq(grid_manager.combo, 1, "undo must roll the combo back with the cell")
	grid_manager.undo_last_move()
	assert_eq(grid_manager.combo, 0, "undoing every move must return the combo to zero")
	# Replaying the same two cells must not exceed what the information supports.
	grid_manager.on_chisel_requested(first)
	grid_manager.on_chisel_requested(second)
	assert_eq(grid_manager.combo, 2, "re-chiselling must not push the combo past the real streak")


func test_undo_does_not_grant_a_second_combo_heal() -> void:
	# Reaching a combo-heal threshold and then undoing back below it must not
	# hand out a second heal for the same information. The restore re-emits
	# combo_updated, so the mechanic has to see a non-multiple and bail out.
	var heal: ComboHealMechanic = ComboHealMechanic.new()
	heal.combo_threshold = 2
	grid_manager.add_child(heal)
	heal.grid_manager = grid_manager
	if not grid_manager.combo_updated.is_connected(heal._on_combo_updated):
		grid_manager.combo_updated.connect(heal._on_combo_updated)
	grid_manager.player_hp = 1
	var cells: Array[Vector3i] = []
	for pos: Vector3i in grid_manager.voxel_states.keys():
		cells.append(pos)
	assert_gte(cells.size(), 3, "the fixture needs room to build and undo a combo")
	grid_manager.on_chisel_requested(cells[0])
	grid_manager.on_chisel_requested(cells[1])
	assert_eq(grid_manager.combo, 2)
	var hp_after_heal: int = grid_manager.player_hp
	assert_gt(hp_after_heal, 1, "reaching the threshold must have healed")
	# Undo rolls the combo back to 1. The re-emit must not heal again.
	grid_manager.undo_last_move()
	assert_eq(grid_manager.combo, 1)
	assert_eq(grid_manager.player_hp, hp_after_heal, "undo must not hand out a second heal")
	# Re-chiselling the same cell is legitimately a fresh 2, so it may heal again,
	# but the combo must still reflect only the real streak.
	grid_manager.on_chisel_requested(cells[1])
	assert_eq(grid_manager.combo, 2, "the combo must not exceed the real streak")


func test_undo_of_a_chained_batch_restores_the_pre_batch_combo() -> void:
	var pos := Vector3i(0, 0, 0)
	grid_manager.on_chisel_requested(Vector3i(1, 1, 1))
	var before_chain: int = grid_manager.combo
	# Simulate a chained batch the way ExplosiveChainMechanic records it: the
	# first entry is the player's own move (combo before it), the rest are the
	# chained cells folded into the same action.
	grid_manager.move_history.append([
		{"pos": pos, "state": GridManager.CellState.UNBROKEN, "target": false, "combo": before_chain},
		{"pos": Vector3i(1, 0, 0), "state": GridManager.CellState.UNBROKEN, "target": false, "combo": before_chain + 1},
	])
	grid_manager.undo_last_move()
	assert_eq(grid_manager.combo, before_chain, "a chained batch must restore the combo from before the batch")


# A kept voxel must never reach DESTROYED through the state primitive, whatever
# calls it. Otherwise a round becomes unwinnable with a perfect mistake count and
# no undo entry.
func test_hammer_cell_refuses_to_destroy_a_kept_voxel() -> void:
	var pos := Vector3i(0, 0, 0)
	grid_manager.target_solution[pos] = true
	grid_manager.voxel_states[pos]["is_target"] = true
	assert_true(grid_manager.is_target_cell(pos))
	assert_false(grid_manager.hammer_cell(pos), "the primitive must refuse to destroy a kept voxel")
	assert_eq(int(grid_manager.voxel_states[pos].get("cell_state", -1)), int(GridManager.CellState.UNBROKEN))
	assert_true(grid_manager.is_cell_unbroken(pos), "a refused chisel must leave the cell intact")
	assert_true(grid_manager.is_cell_correct(pos), "the cell must still count as correct")


func test_hammer_cell_refuses_to_destroy_a_marked_voxel() -> void:
	var pos := Vector3i(1, 0, 0)
	grid_manager.current_mode = GridManager.EditMode.MARK
	grid_manager.on_mark_requested(pos)
	assert_true(grid_manager.is_cell_marked(pos))
	assert_false(grid_manager.hammer_cell(pos), "a marked cell must not be chiselable by the primitive")
	assert_true(grid_manager.is_cell_marked(pos))