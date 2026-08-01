extends GutTest

const GridManager = preload("res://scripts/GridManager.gd")
const BlockClass = preload("res://scripts/Block.gd")
const GameManagerClass = preload("res://scripts/GameManager.gd")
const TimeBombMechanic = preload("res://scripts/TimeBombMechanic.gd")

var grid: GridManager
var bomb_mechanic: TimeBombMechanic

func before_each():
	var gm = Node.new()
	gm.name = "GameManager"
	gm.set_script(GameManagerClass)
	get_tree().root.add_child(gm)

	grid = GridManager.new()
	grid.base_grid_size = 2

	bomb_mechanic = TimeBombMechanic.new()
	bomb_mechanic.is_enabled = true
	bomb_mechanic.bomb_spawn_interval = 1.0 # Fast spawn for testing
	bomb_mechanic.bomb_duration = 0.5 # Fast explode for testing

	grid.add_child(bomb_mechanic)
	add_child_autoqfree(grid)

func after_each():
	var gm = get_tree().root.get_node_or_null("GameManager")
	if gm:
		gm.queue_free()

func test_bomb_spawns_on_unbroken_block():
	grid.start_level()
	grid.is_puzzle_active = true

	grid.target_solution.clear()
	# Set target solution so that we have at least one block that is NOT part of the solution
	grid.target_solution[Vector3i(0, 0, 0)] = true
	grid.target_solution[Vector3i(1, 0, 0)] = false # Valid bomb target

	bomb_mechanic.grid_manager = grid
	bomb_mechanic._ready() # Force ready to hook up signals

	# Fast forward logic
	bomb_mechanic._process(1.5)

	assert_ne(bomb_mechanic.active_bomb_pos, Vector3i(-1, -1, -1), "Bomb should have spawned")
	assert_false(grid.target_solution.get(bomb_mechanic.active_bomb_pos, false), "Bomb should not spawn on a solution block")

func test_bomb_explosion_causes_mistake():
	grid.start_level()
	grid.is_puzzle_active = true

	grid.target_solution.clear()
	grid.target_solution[Vector3i(0, 0, 0)] = true

	bomb_mechanic.grid_manager = grid
	bomb_mechanic._ready() # Force ready to hook up signals

	var initial_hp = grid.player_hp
	var initial_mistakes = grid.mistakes

	# Spawn bomb
	bomb_mechanic._process(1.5)
	var bomb_pos = bomb_mechanic.active_bomb_pos

	assert_ne(bomb_pos, Vector3i(-1, -1, -1), "Bomb should have spawned")
	if bomb_pos == Vector3i(-1, -1, -1): return

	# Fast forward to explosion
	bomb_mechanic._process(1.0)

	assert_eq(bomb_mechanic.active_bomb_pos, Vector3i(-1, -1, -1), "Bomb should have reset after explosion")

	var block = grid.blocks[bomb_pos]
	assert_eq(block.current_state, block.BlockState.DESTROYED, "Bomb block should be destroyed")
	assert_eq(grid.player_hp, initial_hp - 1, "Player should lose HP on bomb explosion")
	assert_eq(grid.mistakes, initial_mistakes + 1, "Player should gain a mistake on bomb explosion")

func test_defusing_bomb_resets_mechanic():
	grid.start_level()
	grid.is_puzzle_active = true

	grid.target_solution.clear()
	grid.target_solution[Vector3i(0, 0, 0)] = true

	bomb_mechanic.grid_manager = grid
	bomb_mechanic._ready() # Force ready to hook up signals

	var initial_hp = grid.player_hp
	var initial_mistakes = grid.mistakes

	# Spawn bomb
	bomb_mechanic._process(1.5)
	var bomb_pos = bomb_mechanic.active_bomb_pos

	assert_ne(bomb_pos, Vector3i(-1, -1, -1), "Bomb should have spawned")
	if bomb_pos == Vector3i(-1, -1, -1): return

	var block = grid.blocks[bomb_pos]
	grid.destroy_block(block) # Player destroys block manually

	assert_eq(bomb_mechanic.active_bomb_pos, Vector3i(-1, -1, -1), "Bomb should have reset after defusal")
	assert_eq(grid.player_hp, initial_hp, "Player should NOT lose HP on defusal")
	assert_eq(grid.mistakes, initial_mistakes, "Player should NOT gain a mistake on defusal")

func test_mechanic_disabled_when_flag_false():
	grid.start_level()
	grid.is_puzzle_active = true

	bomb_mechanic.is_enabled = false
	grid.target_solution.clear()

	bomb_mechanic.grid_manager = grid
	bomb_mechanic._ready() # Force ready to hook up signals

	bomb_mechanic._process(5.0)

	assert_eq(bomb_mechanic.active_bomb_pos, Vector3i(-1, -1, -1), "Bomb should NOT have spawned when disabled")
