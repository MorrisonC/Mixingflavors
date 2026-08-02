extends GutTest

const GridManagerScene = preload("res://scenes/VoxelLogic.tscn")
var grid_manager
var combo_multiplier_mechanic

func before_each():
	grid_manager = GridManagerScene.instantiate()
	grid_manager.base_grid_size = 2
	add_child(grid_manager)

	combo_multiplier_mechanic = grid_manager.get_node_or_null("ComboMultiplierMechanic")
	if combo_multiplier_mechanic:
		combo_multiplier_mechanic.combo_thresholds = [2, 4]
		combo_multiplier_mechanic.multiplier_values = [1.5, 2.0]

func after_each():
	grid_manager.queue_free()

func test_mechanic_initialization():
	assert_not_null(combo_multiplier_mechanic, "ComboMultiplierMechanic node should be instantiated")
	assert_true(combo_multiplier_mechanic.is_enabled, "Mechanic should be enabled by default")

func test_multiplier_updates():
	var signal_spy = watch_signals(combo_multiplier_mechanic)

	grid_manager.combo_updated.emit(1)
	assert_eq(combo_multiplier_mechanic.current_multiplier, 1.0, "Multiplier should remain 1.0 before threshold")

	grid_manager.combo_updated.emit(2)
	assert_eq(combo_multiplier_mechanic.current_multiplier, 1.5, "Multiplier should update to 1.5 at combo 2")

	grid_manager.combo_updated.emit(3)
	assert_eq(combo_multiplier_mechanic.current_multiplier, 1.5, "Multiplier should remain 1.5 at combo 3")

	grid_manager.combo_updated.emit(4)
	assert_eq(combo_multiplier_mechanic.current_multiplier, 2.0, "Multiplier should update to 2.0 at combo 4")
	assert_signal_emit_count(combo_multiplier_mechanic, "multiplier_changed", 2, "Signal should have been emitted twice")
