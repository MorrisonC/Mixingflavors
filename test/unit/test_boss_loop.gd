extends GutTest

const GridManagerScene = preload("res://scenes/VoxelLogic.tscn")
var grid_manager

func before_each():
	grid_manager = GridManagerScene.instantiate()
	grid_manager.base_grid_size = 3
	add_child(grid_manager)

func after_each():
	grid_manager.queue_free()

func test_boss_loop_hp_and_damage():
	assert_eq(grid_manager.player_hp, 3, "Player should start with 3 HP")

	var boss_hp_initial = grid_manager.boss_hp

	# Simulate a mistake
	grid_manager._handle_mistake()
	assert_eq(grid_manager.player_hp, 2, "Player should lose 1 HP on mistake")

	# Force puzzle solved
	grid_manager._reveal_model()
	assert_lt(grid_manager.boss_hp, boss_hp_initial, "Boss HP should decrease after solving puzzle")
