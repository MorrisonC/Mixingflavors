extends GutTest

const EscapeGauntletScene = preload("res://scenes/EscapeGauntlet.tscn")
const GameManagerClass = preload("res://scripts/GameManager.gd")
const PuzzleRegistryClass = preload("res://scripts/PuzzleRegistry.gd")
var gauntlet

func before_each():
	var gm = GameManagerClass.new()
	gm.name = "GameManager"
	get_tree().root.add_child(gm)

	var pr = PuzzleRegistryClass.new()
	pr.name = "PuzzleRegistry"
	get_tree().root.add_child(pr)

	gauntlet = EscapeGauntletScene.instantiate()
	add_child(gauntlet)

func after_each():
	if gauntlet and is_instance_valid(gauntlet):
		gauntlet.queue_free()
	var gm = get_tree().root.get_node_or_null("GameManager")
	if gm:
		gm.queue_free()
	var pr = get_tree().root.get_node_or_null("PuzzleRegistry")
	if pr:
		pr.queue_free()

func test_initialization():
	assert_not_null(gauntlet, "EscapeGauntlet scene should instantiate")
	assert_eq(gauntlet.current_round, 1, "Should start at round 1")
	assert_eq(gauntlet.score, 0, "Should start with 0 score")

func test_round_progression():
	assert_eq(gauntlet.current_round, 1, "Starts at round 1")
	gauntlet._on_puzzle_solved()
	assert_eq(gauntlet.current_round, 2, "Advances to round 2 on puzzle solve")

func test_boss_round():
	gauntlet.current_round = 10
	gauntlet._start_round()
	assert_eq(gauntlet.current_wave_type, "boss", "Round 10 should be a boss wave")

func test_mistake_failure():
	assert_not_null(gauntlet, "Gauntlet should be active")
	gauntlet._on_mistake_made(gauntlet.max_mistakes)
	assert_true(gauntlet.has_node("CanvasLayer"), "Failure UI should attach to CanvasLayer")
