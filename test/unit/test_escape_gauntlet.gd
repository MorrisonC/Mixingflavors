extends GutTest

const EscapeGauntletScene = preload("res://scenes/EscapeGauntlet.tscn")
const GameManagerClass = preload("res://scripts/GameManager.gd")
var gauntlet

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

func after_each():
	gauntlet.queue_free()
	var gm = get_tree().root.get_node_or_null("GameManager")
	if gm:
		gm.queue_free()

	var pr = get_tree().root.get_node_or_null("PuzzleRegistry")
	if pr:
		pr.queue_free()

func test_initialization():
	assert_not_null(gauntlet.active_puzzle, "Active puzzle should be created on initialization")
	assert_eq(gauntlet.current_round, 1, "Initial round should be 1")
	assert_true(gauntlet.time_left > 0, "Initial time should be set")

func test_round_progression():
	gauntlet._on_puzzle_solved()
	assert_eq(gauntlet.current_round, 2, "Round should increase to 2 after solving puzzle")
	assert_true(gauntlet.time_left > 0, "Time should reset for round 2")

func test_boss_round():
	gauntlet._on_puzzle_solved() # To round 2
	gauntlet._on_puzzle_solved() # To round 3
	gauntlet._on_puzzle_solved() # To round 4
	gauntlet._on_puzzle_solved() # To round 5 (boss)
	assert_eq(gauntlet.current_round, 5, "Round should be 5 (max_rounds)")

func test_mistake_failure():
	gauntlet._on_mistake_made(3)
	await get_tree().create_timer(3.5).timeout
	assert_eq(get_node("/root/GameManager").current_mode, GameManagerClass.GameMode.MAIN_MENU, "Failed gauntlet should return to Main Menu")

