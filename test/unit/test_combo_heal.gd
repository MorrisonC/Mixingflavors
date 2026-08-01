extends GutTest

const GridManagerScene = preload("res://scenes/VoxelLogic.tscn")
var grid_manager
var combo_heal_mechanic

func before_each():
	grid_manager = GridManagerScene.instantiate()
	grid_manager.base_grid_size = 2
	add_child(grid_manager)

	combo_heal_mechanic = grid_manager.get_node_or_null("ComboHealMechanic")
	if combo_heal_mechanic:
		combo_heal_mechanic.combo_threshold = 2
		combo_heal_mechanic.heal_amount = 1

func after_each():
	grid_manager.queue_free()

func test_mechanic_initialization():
	assert_not_null(combo_heal_mechanic, "ComboHealMechanic node should be instantiated")
	assert_true(combo_heal_mechanic.is_enabled, "Mechanic should be enabled by default")

func test_heal_below_max_hp():
	grid_manager.player_hp = 1
	grid_manager.combo = 0

	grid_manager.combo_updated.emit(1)
	assert_eq(grid_manager.player_hp, 1, "Should not heal before threshold")

	grid_manager.combo_updated.emit(2)
	assert_eq(grid_manager.player_hp, 2, "Should heal by 1 after reaching threshold of 2")

func test_no_heal_above_max_hp():
	grid_manager.player_hp = 3
	grid_manager.combo = 0

	grid_manager.combo_updated.emit(2)
	assert_eq(grid_manager.player_hp, 3, "Should not heal above max HP")
