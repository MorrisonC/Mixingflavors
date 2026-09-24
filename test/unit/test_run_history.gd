extends GutTest

var manager: RunHistoryManager

func before_each() -> void:
	manager = load("res://scripts/RunHistoryManager.gd").new() as RunHistoryManager
	add_child_autoqfree(manager)
	manager._run_history = []

func after_each() -> void:
	if FileAccess.file_exists(RunHistoryManager.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RunHistoryManager.SAVE_PATH))

func test_record_run() -> void:
	manager.record_run({
		"mode": "easy",
		"status": "completed",
		"total_time_seconds": 120.0
	})
	var all_runs: Array = manager.get_all_runs()
	assert_eq(all_runs.size(), 1)
	assert_has(all_runs[0], "run_id")
	assert_has(all_runs[0], "timestamp")

func test_aggregate_stats() -> void:
	manager.record_run({"mode": "easy", "status": "completed", "total_time_seconds": 60.0, "difficulty_breakdown": {"easy": 2, "medium": 0}})
	manager.record_run({"mode": "hard", "status": "failed", "total_time_seconds": 30.0, "difficulty_breakdown": {"easy": 1, "hard": 1}})
	var stats: Dictionary = manager.get_aggregate_stats()
	assert_eq(stats["total_runs"], 2)
	assert_eq(stats["total_time_spent"], 90.0)
	assert_eq(stats["avg_run_time"], 45.0)
	assert_eq(stats["clear_rate"], 0.5)
	assert_eq(stats["fastest_run_time"], 60.0)
	assert_eq(stats["total_puzzles_by_tier"]["easy"], 3)
