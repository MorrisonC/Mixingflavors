extends GutTest

const GridManagerClass = preload("res://scripts/GridManager.gd")
const TimeBombMechanicClass = preload("res://scripts/TimeBombMechanic.gd")

var grid: GridManager
var bomb_mechanic: TimeBombMechanic
var _owns_game_manager: bool = false

func before_each() -> void:
	var game_manager: Node = get_tree().root.get_node_or_null("GameManager")
	if not game_manager:
		game_manager = Node.new()
		game_manager.name = "GameManager"
		game_manager.set_script(preload("res://scripts/GameManager.gd"))
		get_tree().root.add_child(game_manager)
		_owns_game_manager = true

	grid = GridManagerClass.new()
	grid.base_grid_size = 2
	bomb_mechanic = TimeBombMechanicClass.new()
	bomb_mechanic.is_enabled = true
	bomb_mechanic.bomb_spawn_interval = 1.0
	bomb_mechanic.bomb_duration = 0.5
	grid.add_child(bomb_mechanic)
	add_child_autoqfree(grid)
	grid.start_level()
	_set_only_target(Vector3i(0, 0, 0))
	grid.is_puzzle_active = true
	grid.input_locked = false

func after_each() -> void:
	if _owns_game_manager:
		var game_manager := get_tree().root.get_node_or_null("GameManager")
		if game_manager:
			game_manager.queue_free()

func _set_only_target(target_pos: Vector3i) -> void:
	grid.target_shape.clear()
	for pos: Vector3i in grid.voxel_states.keys():
		grid.target_solution[pos] = pos == target_pos
		grid.voxel_states[pos]["is_target"] = pos == target_pos
		if pos == target_pos:
			grid.target_shape.append(pos)
	grid._update_clues()

func test_bomb_spawns_on_unbroken_non_target() -> void:
	bomb_mechanic._process(1.5)
	assert_ne(bomb_mechanic.active_bomb_pos, Vector3i(-1, -1, -1), "Bomb should have spawned")
	assert_false(bomb_mechanic.active_bomb_pos in grid.target_shape, "Bomb should not spawn on a target")

func test_bomb_explosion_causes_mistake() -> void:
	var initial_hp: int = grid.player_hp
	var initial_mistakes: int = grid.mistakes
	bomb_mechanic._process(1.5)
	var bomb_pos: Vector3i = bomb_mechanic.active_bomb_pos
	assert_ne(bomb_pos, Vector3i(-1, -1, -1), "Bomb should have spawned")
	bomb_mechanic._process(1.0)
	assert_eq(bomb_mechanic.active_bomb_pos, Vector3i(-1, -1, -1), "Bomb should reset after explosion")
	assert_eq(grid.blocks[bomb_pos].current_state, VoxelBlock.BlockState.DESTROYED)
	assert_eq(grid.player_hp, initial_hp - 1)
	assert_eq(grid.mistakes, initial_mistakes + 1)

func test_defusing_bomb_resets_mechanic_without_penalty() -> void:
	var initial_hp: int = grid.player_hp
	var initial_mistakes: int = grid.mistakes
	bomb_mechanic._process(1.5)
	var bomb_pos: Vector3i = bomb_mechanic.active_bomb_pos
	assert_ne(bomb_pos, Vector3i(-1, -1, -1), "Bomb should have spawned")
	grid.destroy_block(grid.blocks[bomb_pos] as VoxelBlock)
	assert_eq(bomb_mechanic.active_bomb_pos, Vector3i(-1, -1, -1), "Bomb should reset after defusal")
	assert_eq(grid.player_hp, initial_hp)
	assert_eq(grid.mistakes, initial_mistakes)

func test_mechanic_disabled_when_flag_false() -> void:
	bomb_mechanic.is_enabled = false
	bomb_mechanic._process(5.0)
	assert_eq(bomb_mechanic.active_bomb_pos, Vector3i(-1, -1, -1))

# Clue hosts are lightweight VoxelBlock nodes with no per-block material, so the
# bomb pulse must be drawn by the mechanic's own overlay. This asserts the
# visual actually exists, which it did not before the overlay was added.
func test_bomb_pulse_uses_the_mechanic_overlay_not_a_block_material() -> void:
	bomb_mechanic._process(1.5)
	var bomb_pos: Vector3i = bomb_mechanic.active_bomb_pos
	assert_ne(bomb_pos, Vector3i(-1, -1, -1), "Bomb should have spawned")
	assert_null((grid.blocks[bomb_pos] as VoxelBlock).base_material, "clue hosts must stay material-less")
	var overlay := bomb_mechanic._ensure_bomb_visual()
	assert_not_null(overlay, "bomb overlay should be created on demand")
	assert_true(overlay.visible, "overlay should be visible while a bomb is active")
	assert_eq(overlay.position, (grid.blocks[bomb_pos] as VoxelBlock).position)
	var material := overlay.mesh.surface_get_material(0) as StandardMaterial3D
	assert_not_null(material)
	assert_true(material.emission_enabled, "bomb overlay should emit so it reads over the glass blocks")
	assert_gt(material.albedo_color.a, 0.0, "bomb overlay must not be fully transparent")

func test_bomb_overlay_is_hidden_after_reset() -> void:
	bomb_mechanic._process(1.5)
	var bomb_pos: Vector3i = bomb_mechanic.active_bomb_pos
	assert_ne(bomb_pos, Vector3i(-1, -1, -1), "Bomb should have spawned")
	grid.destroy_block(grid.blocks[bomb_pos] as VoxelBlock)
	assert_false(bomb_mechanic._ensure_bomb_visual().visible, "overlay must hide once the bomb is gone")

func test_bomb_overlay_hides_when_the_mechanic_is_disabled_mid_bomb() -> void:
	bomb_mechanic._process(1.5)
	assert_ne(bomb_mechanic.active_bomb_pos, Vector3i(-1, -1, -1), "Bomb should have spawned")
	assert_true(bomb_mechanic._ensure_bomb_visual().visible)
	bomb_mechanic.is_enabled = false
	bomb_mechanic._process(0.1)
	assert_eq(bomb_mechanic.active_bomb_pos, Vector3i(-1, -1, -1))
	assert_false(bomb_mechanic._ensure_bomb_visual().visible, "disabling must clear the bomb overlay")
