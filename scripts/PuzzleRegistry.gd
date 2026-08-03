extends Node
class_name PuzzleRegistryClass

var manifest_data: Dictionary = {}
var loaded_theme_puzzles: Dictionary = {}

func _ready() -> void:
	load_manifest()

func load_manifest() -> void:
	var path = "res://assets/puzzles/puzzle_manifest.json"
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		manifest_data = JSON.parse_string(file.get_as_text()).get("themes", {})

func load_theme(theme_name: String) -> Array:
	if loaded_theme_puzzles.has(theme_name):
		return loaded_theme_puzzles[theme_name]

	var file_info = manifest_data.get(theme_name, {})
	var file_name = file_info.get("file", "")
	var full_path = "res://assets/puzzles/" + file_name

	if FileAccess.file_exists(full_path):
		var file = FileAccess.open(full_path, FileAccess.READ)
		var parsed = JSON.parse_string(file.get_as_text())
		var puzzles = parsed.get("puzzles", [])
		var valid_puzzles = []

		# Validator integration
		var SolvabilityValidator = load("res://scripts/SolvabilityValidator.gd")
		for puzzle in puzzles:
			if SolvabilityValidator and SolvabilityValidator.has_method("is_puzzle_solvable"):
				if SolvabilityValidator.is_puzzle_solvable(puzzle):
					valid_puzzles.append(puzzle)
				else:
					print("[PuzzleRegistry] Puzzle failed solvability validation, skipping: ", puzzle.get("id", "Unknown"))
			else:
				valid_puzzles.append(puzzle)

		loaded_theme_puzzles[theme_name] = valid_puzzles
		return valid_puzzles
	return []

func get_puzzles_for_gauntlet(tier: String) -> Array:
	var matching_puzzles: Array = []
	var themes = manifest_data.keys()
	if themes.size() > 0:
		# Just load a random theme rather than ALL 16 to save memory
		var rand_theme = themes[randi() % themes.size()]
		var puzzles = load_theme(rand_theme)
		for puzzle in puzzles:
			if puzzle.get("difficulty_tier", "") == tier:
				matching_puzzles.append(puzzle)

		# If somehow we didn't find any for this tier, fallback to checking loaded ones
		if matching_puzzles.is_empty():
			for loaded_theme in loaded_theme_puzzles.keys():
				for puzzle in loaded_theme_puzzles[loaded_theme]:
					if puzzle.get("difficulty_tier", "") == tier:
						matching_puzzles.append(puzzle)
	return matching_puzzles

func get_all_puzzles() -> Array:
	var all_puzzles: Array = []
	for theme in manifest_data.keys():
		all_puzzles.append_array(load_theme(theme))
	return all_puzzles

func get_puzzles_by_tier(tier: String) -> Array:
	return get_puzzles_for_gauntlet(tier)

func get_puzzles_by_score_range(min_score: int, max_score: int) -> Array:
	var result: Array = []
	var puzzles = get_all_puzzles()
	for p in puzzles:
		var score = p.get("difficulty_score", 0)
		if score >= min_score and score <= max_score:
			result.append(p)
	return result
