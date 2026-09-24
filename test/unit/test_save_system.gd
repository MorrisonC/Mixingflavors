extends GutTest

const SaveSystemClass = preload("res://scripts/SaveSystem.gd")
const TEST_SAVE_PATH: String = "user://test_save_data.json"

var save_system: Node

func before_each() -> void:
	_remove_test_save()
	save_system = SaveSystemClass.new()
	save_system.set("save_path", TEST_SAVE_PATH)
	add_child_autoqfree(save_system)

func after_each() -> void:
	_remove_test_save()

func _remove_test_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(absolute_path)

func test_initial_save_data() -> void:
	assert_eq(save_system.get("save_data")["completed_puzzles"].size(), 0)
	assert_eq(save_system.get("save_data")["current_wave"], 0)
	assert_eq(save_system.get("save_data")["settings"]["sfx_vol"], 1.0)

func test_save_and_load_game() -> void:
	var save_data: Dictionary = save_system.get("save_data")
	save_data["completed_puzzles"].append("level_1")
	save_data["current_wave"] = 5
	save_data["settings"]["sfx_vol"] = 0.5
	save_system.call("save_game")

	var loaded_save_system := SaveSystemClass.new()
	loaded_save_system.set("save_path", TEST_SAVE_PATH)
	add_child_autoqfree(loaded_save_system)
	loaded_save_system.call("load_game")
	var loaded_data: Dictionary = loaded_save_system.get("save_data")
	assert_true(loaded_data["completed_puzzles"].has("level_1"))
	assert_eq(int(loaded_data["current_wave"]), 5)
	assert_eq(float(loaded_data["settings"]["sfx_vol"]), 0.5)
