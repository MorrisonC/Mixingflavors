extends GutTest

const EscapeGauntletScene: PackedScene = preload("res://scenes/EscapeGauntlet.tscn")
const GameManagerClass = preload("res://scripts/GameManager.gd")

var gauntlet: Node3D

func before_each() -> void:
	var game_manager := GameManagerClass.new()
	game_manager.name = "GameManager"
	get_tree().root.add_child(game_manager)
	var registry := PuzzleRegistryClass.new()
	registry.name = "PuzzleRegistry"
	get_tree().root.add_child(registry)
	gauntlet = EscapeGauntletScene.instantiate() as Node3D
	add_child_autoqfree(gauntlet)

func after_each() -> void:
	var game_manager := get_tree().root.get_node_or_null("GameManager")
	if game_manager:
		game_manager.queue_free()
	var registry := get_tree().root.get_node_or_null("PuzzleRegistry")
	if registry:
		registry.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func test_initialization() -> void:
	assert_not_null(gauntlet.active_puzzle)
	assert_eq(gauntlet.current_round, 1)
	assert_gt(gauntlet.time_left, 0.0)

func test_round_progression() -> void:
	gauntlet.call("_on_puzzle_solved")
	await get_tree().process_frame
	assert_eq(gauntlet.current_round, 2)
	assert_gt(gauntlet.time_left, 0.0)

func test_boss_round() -> void:
	for expected_round: int in range(2, 6):
		gauntlet.call("_on_puzzle_solved")
		await get_tree().process_frame
		assert_eq(gauntlet.current_round, expected_round)
	assert_eq(gauntlet.current_wave_type, "boss")

func test_mistake_failure_opens_game_over_without_silent_mode_switch() -> void:
	gauntlet.call("_on_mistake_made", 3)
	assert_true(gauntlet.is_game_over)
	assert_true((gauntlet.get_node("CanvasLayer/UI/GameOver") as Control).visible)
	assert_eq(get_tree().root.get_node("GameManager").current_mode, GameManagerClass.GameMode.MAIN_MENU)
