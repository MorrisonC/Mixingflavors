extends Node

const SAVE_PATH = "user://run_history.json"
var _run_history: Array = []

func _ready() -> void:
	_load_history()

func _load_history() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			file.close()
			var parsed = JSON.parse_string(content)
			if parsed is Array:
				_run_history = parsed

func _save_history() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_run_history, "\t"))
		file.close()

func record_run(run_data: Dictionary) -> void:
	# Ensure basic required fields exist
	if not run_data.has("run_id"):
		run_data["run_id"] = _generate_uuid()
	if not run_data.has("timestamp"):
		run_data["timestamp"] = Time.get_datetime_string_from_system()

	_run_history.append(run_data)
	_save_history()

func get_all_runs() -> Array:
	return _run_history

func get_aggregate_stats() -> Dictionary:
	var total_runs: int = _run_history.size()
	var total_time_spent: float = 0.0
	var completed_runs: int = 0
	var fastest_run_time: float = INF

	var total_puzzles_by_tier = {
		"easy": 0,
		"medium": 0,
		"hard": 0,
		"boss": 0
	}

	for run in _run_history:
		total_time_spent += run.get("total_time_seconds", 0.0)

		if run.get("status", "") == "completed":
			completed_runs += 1
			var t = run.get("total_time_seconds", 0.0)
			if t < fastest_run_time:
				fastest_run_time = t

		var breakdown = run.get("difficulty_breakdown", {})
		total_puzzles_by_tier["easy"] += breakdown.get("easy", 0)
		total_puzzles_by_tier["medium"] += breakdown.get("medium", 0)
		total_puzzles_by_tier["hard"] += breakdown.get("hard", 0)
		total_puzzles_by_tier["boss"] += breakdown.get("boss", 0)

	var avg_run_time: float = 0.0
	if total_runs > 0:
		avg_run_time = total_time_spent / float(total_runs)

	var clear_rate: float = 0.0
	if total_runs > 0:
		clear_rate = float(completed_runs) / float(total_runs)

	if fastest_run_time == INF:
		fastest_run_time = 0.0

	return {
		"total_runs": total_runs,
		"total_time_spent": total_time_spent,
		"avg_run_time": avg_run_time,
		"fastest_run_time": fastest_run_time,
		"total_puzzles_by_tier": total_puzzles_by_tier,
		"clear_rate": clear_rate
	}

func _generate_uuid() -> String:
	# A simple UUID v4 generator
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var bytes = []
	for i in range(16):
		bytes.append(rng.randi_range(0, 255))

	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80

	var uuid = ""
	for i in range(16):
		var hex = "%02x" % bytes[i]
		uuid += hex
		if i == 3 or i == 5 or i == 7 or i == 9:
			uuid += "-"

	return uuid
