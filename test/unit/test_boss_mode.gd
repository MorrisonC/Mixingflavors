extends GutTest

const EscapeGauntletScene = preload("res://scenes/EscapeGauntlet.tscn")
const GameManagerClass = preload("res://scripts/GameManager.gd")
const PuzzleRegistryClass = preload("res://scripts/PuzzleRegistry.gd")
var gauntlet

func before_each():
	var gm = GameManagerClass.new()
	gm.name = "GameManager"
	gm.selected_difficulty_mode = "boss"
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

func test_boss_mode_initialization():
	assert_eq(get_node("/root/GameManager").selected_difficulty_mode, "boss", "GameManager should be in boss mode")
	assert_not_null(gauntlet.active_puzzle, "Active puzzle should be initialized in boss mode")

	await get_tree().process_frame

	var puzzle_data = gauntlet.active_puzzle.custom_puzzle_data
	assert_typeof(puzzle_data, TYPE_DICTIONARY, "Puzzle data should be a dictionary")
