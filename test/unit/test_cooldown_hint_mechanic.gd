extends GutTest

const GridManagerScene: PackedScene = preload("res://scenes/VoxelLogic.tscn")

var grid_manager: GridManager
var hint_mechanic: CooldownHintMechanic

func before_each() -> void:
	grid_manager = GridManagerScene.instantiate()
	grid_manager.base_grid_size = 2
	add_child_autoqfree(grid_manager)
	hint_mechanic = grid_manager.get_node_or_null("CooldownHintMechanic") as CooldownHintMechanic

func test_mechanic_initialization() -> void:
	assert_not_null(hint_mechanic)
	assert_true(hint_mechanic.is_enabled)
	assert_true(hint_mechanic.is_ready)

func test_hint_updates_canonical_target_state() -> void:
	var target_pos := Vector3i(0, 0, 0)
	grid_manager.target_solution[target_pos] = true
	grid_manager.voxel_states[target_pos]["is_target"] = true
	grid_manager.target_shape.append(target_pos)
	assert_true(hint_mechanic.use_hint())
	assert_false(hint_mechanic.is_ready)
	assert_true(grid_manager.is_cell_marked(target_pos))
	assert_eq(grid_manager.blocks[target_pos].current_state, VoxelBlock.BlockState.MARKED)
	assert_eq(int(grid_manager.voxel_states[target_pos]["cell_state"]), GridManager.CellState.MARKED)

func test_hint_destroys_non_target_through_canonical_state() -> void:
	var empty_pos := Vector3i(0, 0, 0)
	grid_manager.target_solution[empty_pos] = false
	grid_manager.voxel_states[empty_pos]["is_target"] = false
	assert_true(hint_mechanic.use_hint())
	assert_true(grid_manager.is_cell_chiseled(empty_pos))
	assert_eq(grid_manager.blocks[empty_pos].current_state, VoxelBlock.BlockState.DESTROYED)

func test_cooldown_recharge() -> void:
	hint_mechanic.cooldown_duration = 0.5
	assert_true(hint_mechanic.use_hint())
	assert_false(hint_mechanic.is_ready)
	hint_mechanic._process(0.6)
	assert_true(hint_mechanic.is_ready)
