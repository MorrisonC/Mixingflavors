extends Node
class_name PuzzleRegistryClass

## Lazy, cached loader for shipped puzzle themes.  Raw JSON is normalized
## once at this boundary; callers receive only canonical dictionaries.

const PuzzleDataValidatorClass = preload("res://scripts/PuzzleDataValidator.gd")
const MANIFEST_PATH: String = "res://assets/puzzles/puzzle_manifest.json"
const PUZZLE_DIRECTORY: String = "res://assets/puzzles/"

var manifest_data: Dictionary = {}
var loaded_theme_puzzles: Dictionary = {}
var theme_load_stats: Dictionary = {}
var aggregate_load_stats: Dictionary = {
	"themes_loaded": 0,
	"puzzles_seen": 0,
	"puzzles_loaded": 0,
	"puzzles_rejected": 0,
	"puzzles_repaired": 0,
	"statuses": {},
}

func _ready() -> void:
	if manifest_data.is_empty():
		load_manifest()

func load_manifest() -> void:
	manifest_data = {}
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var file: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary and parsed.get("themes", {}) is Dictionary:
		manifest_data = parsed.get("themes", {})

func load_theme(theme_name: String) -> Array:
	if loaded_theme_puzzles.has(theme_name):
		return loaded_theme_puzzles[theme_name]
	var valid_puzzles: Array = []
	var stats: Dictionary = {"theme": theme_name, "seen": 0, "loaded": 0, "rejected": 0, "repaired": 0, "statuses": {}}
	var file_info: Dictionary = _theme_file_info(theme_name)
	var file_name: String = str(file_info.get("file", ""))
	var full_path: String = PUZZLE_DIRECTORY + file_name
	if file_name.is_empty() or not FileAccess.file_exists(full_path):
		return _finish_theme(theme_name, valid_puzzles, stats, 1)
	var file: FileAccess = FileAccess.open(full_path, FileAccess.READ)
	if file == null:
		return _finish_theme(theme_name, valid_puzzles, stats, 1)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return _finish_theme(theme_name, valid_puzzles, stats, 1)
	var raw_puzzles: Array = []
	var puzzle_collection: Variant = parsed.get("puzzles", null)
	if puzzle_collection is Array:
		raw_puzzles = puzzle_collection
	elif parsed.has("dims") or parsed.has("grid_size"):
		# Standalone shipped puzzle files are valid theme entries too.
		raw_puzzles.append(parsed)
	else:
		return _finish_theme(theme_name, valid_puzzles, stats, 1)
	stats["seen"] = raw_puzzles.size()
	for raw_puzzle: Variant in raw_puzzles:
		if not raw_puzzle is Dictionary:
			stats["rejected"] += 1
			_record_status(stats, PuzzleDataValidatorClass.STATUS_INVALID)
			continue
		var analysis: Dictionary = PuzzleDataValidatorClass.analyze_puzzle(raw_puzzle, true)
		var status: String = str(analysis.get("status", PuzzleDataValidatorClass.STATUS_INVALID))
		_record_status(stats, status)
		if bool(analysis.get("was_repaired", false)):
			stats["repaired"] += 1
		if not bool(analysis.get("ok", false)):
			stats["rejected"] += 1
			continue
		var canonical: Variant = analysis.get("puzzle", {})
		if not canonical is Dictionary or canonical.is_empty():
			stats["rejected"] += 1
			continue
		valid_puzzles.append(canonical)
		stats["loaded"] += 1
	return _finish_theme(theme_name, valid_puzzles, stats, 0)

func get_puzzles_for_gauntlet(tier: String) -> Array:
	var matching: Array = []
	var themes: Array = manifest_data.keys()
	themes.shuffle()
	for theme: Variant in themes:
		for puzzle: Dictionary in load_theme(str(theme)):
			if str(puzzle.get("difficulty_tier", "")) == tier:
				matching.append(puzzle)
		if not matching.is_empty():
			return matching
	return matching

func get_all_puzzles() -> Array:
	var all_puzzles: Array = []
	for theme: Variant in manifest_data.keys():
		all_puzzles.append_array(load_theme(str(theme)))
	return all_puzzles

func get_puzzles_by_tier(tier: String) -> Array:
	return get_puzzles_for_gauntlet(tier)

func get_puzzles_by_score_range(min_score: int, max_score: int) -> Array:
	var result: Array = []
	for puzzle: Dictionary in get_all_puzzles():
		var score_value: Variant = puzzle.get("difficulty_score", 0)
		if _is_integer_value(score_value) and int(score_value) >= min_score and int(score_value) <= max_score:
			result.append(puzzle)
	return result

func get_theme_load_stats(theme_name: String) -> Dictionary:
	return theme_load_stats.get(theme_name, {})

func get_load_stats(theme_name: String = "") -> Dictionary:
	if theme_name.is_empty():
		return get_aggregate_load_stats()
	return get_theme_load_stats(theme_name)

func get_aggregate_load_stats() -> Dictionary:
	return aggregate_load_stats.duplicate(true)

func clear_theme_cache() -> void:
	loaded_theme_puzzles.clear()
	theme_load_stats.clear()
	aggregate_load_stats["themes_loaded"] = 0
	aggregate_load_stats["puzzles_seen"] = 0
	aggregate_load_stats["puzzles_loaded"] = 0
	aggregate_load_stats["puzzles_rejected"] = 0
	aggregate_load_stats["puzzles_repaired"] = 0
	aggregate_load_stats["statuses"] = {}

func _finish_theme(theme_name: String, valid_puzzles: Array, stats: Dictionary, missing_rejections: int) -> Array:
	stats["rejected"] = int(stats["rejected"]) + missing_rejections
	loaded_theme_puzzles[theme_name] = valid_puzzles
	theme_load_stats[theme_name] = stats
	aggregate_load_stats["themes_loaded"] = int(aggregate_load_stats["themes_loaded"]) + 1
	aggregate_load_stats["puzzles_seen"] = int(aggregate_load_stats["puzzles_seen"]) + int(stats["seen"])
	aggregate_load_stats["puzzles_loaded"] = int(aggregate_load_stats["puzzles_loaded"]) + int(stats["loaded"])
	aggregate_load_stats["puzzles_rejected"] = int(aggregate_load_stats["puzzles_rejected"]) + int(stats["rejected"])
	aggregate_load_stats["puzzles_repaired"] = int(aggregate_load_stats["puzzles_repaired"]) + int(stats["repaired"])
	var aggregate_statuses: Dictionary = aggregate_load_stats["statuses"]
	var theme_statuses: Dictionary = stats.get("statuses", {})
	for status: Variant in theme_statuses.keys():
		var status_name: String = str(status)
		aggregate_statuses[status_name] = int(aggregate_statuses.get(status_name, 0)) + int(theme_statuses[status])
	if int(stats["seen"]) > 0 or int(stats["rejected"]) > 0:
		print("[PuzzleRegistry] theme=", theme_name, " seen=", int(stats["seen"]), " loaded=", int(stats["loaded"]), " rejected=", int(stats["rejected"]), " repaired=", int(stats["repaired"]), " statuses=", str(stats["statuses"]))
	return valid_puzzles

func _theme_file_info(theme_name: String) -> Dictionary:
	var value: Variant = manifest_data.get(theme_name, {})
	if value is Dictionary:
		return value
	if value is String:
		return {"file": value}
	return {}

func _record_status(stats: Dictionary, status: String) -> void:
	var statuses: Dictionary = stats["statuses"]
	statuses[status] = int(statuses.get(status, 0)) + 1

func _is_integer_value(value: Variant) -> bool:
	var value_type: int = typeof(value)
	if value_type == TYPE_INT:
		return true
	if value_type != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and floor(number) == number
