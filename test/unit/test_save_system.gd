extends GutTest

const SaveSystemClass = preload("res://scripts/SaveSystem.gd")
var save_system

func before_each():
	save_system = SaveSystemClass.new()
	save_system.save_path = "user://test_save_data.json"
	add_child(save_system)

	if FileAccess.file_exists(save_system.save_path):
		DirAccess.remove_absolute(save_system.save_path)

func after_each():
	save_system.queue_free()
	if FileAccess.file_exists("user://test_save_data.json"):
		DirAccess.remove_absolute("user://test_save_data.json")

func test_initial_save_data():
	assert_eq(save_system.save_data["completed_puzzles"].size(), 0)
	assert_eq(save_system.save_data["current_wave"], 0)
	assert_eq(save_system.save_data["settings"]["sfx_vol"], 1.0)

func test_save_and_load_game():
	save_system.save_data["completed_puzzles"].append("level_1")
	save_system.save_data["current_wave"] = 5
	save_system.save_data["settings"]["sfx_vol"] = 0.5

	save_system.save_game()

	var new_save_system = SaveSystemClass.new()
	new_save_system.save_path = "user://test_save_data.json"
	add_child(new_save_system)

	# Simulates read access logic inside new SaveSystem instance
	new_save_system.load_game()

	assert_true(new_save_system.save_data["completed_puzzles"].has("level_1"))
	assert_eq(new_save_system.save_data["current_wave"], 5)
	assert_eq(new_save_system.save_data["settings"]["sfx_vol"], 0.5)

	new_save_system.queue_free()
