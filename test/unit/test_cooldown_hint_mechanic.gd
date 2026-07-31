extends GutTest

const GridManagerScene = preload("res://scenes/VoxelLogic.tscn")
var grid_manager
var hint_mechanic

func before_each():
	grid_manager = GridManagerScene.instantiate()
	grid_manager.base_grid_size = 2
	add_child(grid_manager)

	hint_mechanic = grid_manager.get_node_or_null("CooldownHintMechanic")

func after_each():
	grid_manager.queue_free()

func test_mechanic_initialization():
	assert_not_null(hint_mechanic, "CooldownHintMechanic node should be instantiated")
	assert_true(hint_mechanic.is_enabled, "Mechanic should be enabled by default")
	assert_true(hint_mechanic.is_ready, "Mechanic should be ready initially")

func test_hint_usage():
	grid_manager.target_solution[Vector3i(0, 0, 0)] = true

	var initial_ready = hint_mechanic.is_ready
	assert_true(initial_ready, "Hint should be ready initially")

	var result = hint_mechanic.use_hint()

	assert_true(result, "use_hint() should return true on success")
	assert_false(hint_mechanic.is_ready, "Hint should no longer be ready after use")

	# Since it's a target, it should be marked
	assert_true(grid_manager.blocks[Vector3i(0, 0, 0)].current_state == grid_manager.blocks[Vector3i(0,0,0)].BlockState.MARKED, "Target block should be marked by hint")

func test_cooldown_recharge():
	grid_manager.target_solution[Vector3i(0, 0, 0)] = true
	hint_mechanic.cooldown_duration = 0.5
	hint_mechanic.use_hint()

	assert_false(hint_mechanic.is_ready, "Should be on cooldown")

	# Simulate time passing
	hint_mechanic._process(0.6)

	assert_true(hint_mechanic.is_ready, "Should be ready again after cooldown duration passes")
