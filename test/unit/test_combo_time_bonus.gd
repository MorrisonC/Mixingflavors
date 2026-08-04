
extends GutTest

const PuzzleRegistryClass = preload("res://scripts/PuzzleRegistry.gd")

const EscapeGauntletScene = preload("res://scenes/EscapeGauntlet.tscn")
const GameManagerClass = preload("res://scripts/GameManager.gd")
var gauntlet
var time_bonus_mechanic

func before_each():
	# Mock GameManager Autoload
	var gm = GameManagerClass.new()
	gm.name = "GameManager"
	get_tree().root.add_child(gm)

	var pr = PuzzleRegistryClass.new()
	pr.name = "PuzzleRegistry"
	get_tree().root.add_child(pr)

	gauntlet = EscapeGauntletScene.instantiate()
	add_child(gauntlet)

	time_bonus_mechanic = gauntlet.active_puzzle.get_node_or_null("ComboTimeBonusMechanic")

func after_each():
	gauntlet.queue_free()
	var gm = get_tree().root.get_node_or_null("GameManager")
	if gm:
		gm.queue_free()

	var pr = get_tree().root.get_node_or_null("PuzzleRegistry")
	if pr:
		pr.queue_free()

func test_mechanic_initialization():
	assert_not_null(time_bonus_mechanic, "ComboTimeBonusMechanic node should be instantiated")
	assert_true(time_bonus_mechanic.is_enabled, "Mechanic should be enabled by default")

func test_time_bonus_applied_on_combo():
	var initial_time = gauntlet.time_left

	# Simulate 4 combo (no bonus yet)
	gauntlet.active_puzzle.combo = 4
	gauntlet.active_puzzle.combo_updated.emit(4)

	assert_eq(gauntlet.time_left, initial_time, "Time left should not increase before threshold")

	# Simulate 5 combo (bonus threshold)
	gauntlet.active_puzzle.combo = 5
	gauntlet.active_puzzle.combo_updated.emit(5)

	assert_eq(gauntlet.time_left, initial_time + time_bonus_mechanic.time_bonus, "Time left should increase by time_bonus at threshold")

func test_time_bonus_applied_on_multiple_combo():
	var initial_time = gauntlet.time_left

	# Simulate 10 combo (bonus threshold x2)
	gauntlet.active_puzzle.combo = 10
	gauntlet.active_puzzle.combo_updated.emit(10)

	assert_eq(gauntlet.time_left, initial_time + time_bonus_mechanic.time_bonus, "Time left should increase by time_bonus at second threshold")
