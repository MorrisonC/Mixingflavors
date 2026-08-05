extends GutTest

const GridManagerClass = preload("res://scripts/GridManager.gd")
const ComboMultiplierClass = preload("res://scripts/ComboMultiplierMechanic.gd")

var grid_manager
var mechanic

func before_each():
	grid_manager = GridManagerClass.new()
	add_child(grid_manager)

	mechanic = ComboMultiplierClass.new()
	grid_manager.add_child(mechanic)

	# Manually trigger ready and force connection
	mechanic._ready()

func after_each():
	if is_instance_valid(grid_manager):
		grid_manager.queue_free()

func test_mechanic_initialization():
	assert_true(mechanic.is_enabled, "Mechanic should be enabled by default")
	assert_eq(mechanic.current_multiplier, 1.0, "Multiplier should start at 1.0")
	assert_not_null(mechanic.grid_manager, "Should find grid manager parent")

func test_multiplier_increases_at_threshold():
	# Trigger combo to reach threshold
	for i in range(mechanic.combo_threshold):
		grid_manager.combo_updated.emit(i + 1)

	assert_eq(mechanic.current_multiplier, 1.0 + mechanic.multiplier_increment, "Multiplier should increase by increment at threshold")

func test_multiplier_caps_at_max():
	# Artificially lower max for faster test
	mechanic.max_multiplier = 1.2
	mechanic.multiplier_increment = 0.1
	mechanic.combo_threshold = 2

	# Trigger enough combos to exceed max
	for i in range(10):
		grid_manager.combo_updated.emit(i + 1)

	assert_eq(mechanic.current_multiplier, mechanic.max_multiplier, "Multiplier should not exceed max")

func test_multiplier_resets_on_combo_break():
	# Increase multiplier
	for i in range(mechanic.combo_threshold):
		grid_manager.combo_updated.emit(i + 1)

	assert_true(mechanic.current_multiplier > 1.0, "Multiplier should be > 1.0 before reset")

	# Break combo
	grid_manager.combo_updated.emit(0)

	assert_eq(mechanic.current_multiplier, 1.0, "Multiplier should reset to 1.0 when combo is broken (0)")
