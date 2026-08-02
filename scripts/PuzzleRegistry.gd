class_name PuzzleRegistry
extends Node

static func get_all_puzzles() -> Array[Dictionary]:
	var puzzles: Array[Dictionary] = []
	var base_path = "res://assets/puzzles/"
	var base_dir = DirAccess.open(base_path)
	if base_dir:
		base_dir.list_dir_begin()
		var d = base_dir.get_next()
		while d != "":
			if base_dir.current_is_dir() and d != "." and d != "..":
				var path = base_path + d + "/"
				var dir = DirAccess.open(path)
				if dir:
					dir.list_dir_begin()
					var file_name = dir.get_next()
					while file_name != "":
						if not dir.current_is_dir() and file_name.ends_with(".json"):
							var file_path = path + file_name
							var file = FileAccess.open(file_path, FileAccess.READ)
							if file:
								var json_text = file.get_as_text()
								file.close()
								var puzzle_data = JSON.parse_string(json_text)
								if puzzle_data:
									puzzles.append(puzzle_data)
						file_name = dir.get_next()
			d = base_dir.get_next()
	return puzzles

static func get_puzzles_by_tier(tier: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var puzzles = get_all_puzzles()
	for p in puzzles:
		if p.get("difficulty_tier", "medium") == tier:
			result.append(p)
	return result

static func get_puzzles_by_score_range(min_score: int, max_score: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var puzzles = get_all_puzzles()
	for p in puzzles:
		var score = p.get("difficulty_score", 0)
		if score >= min_score and score <= max_score:
			result.append(p)
	return result
