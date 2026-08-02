extends GutTest

var manager = null

func before_each():
	manager = load("res://scripts/RunHistoryManager.gd").new()
	# clear history for test isolation
	manager._run_history = []

func test_record_run():
	var run = {
		"mode": "easy",
		"status": "completed",
		"total_time_seconds": 120.0
	}
	manager.record_run(run)

	var all_runs = manager.get_all_runs()
	assert_eq(all_runs.size(), 1, "Should have 1 run recorded")
	assert_has(all_runs[0], "run_id", "Run should have auto-generated run_id")
	assert_has(all_runs[0], "timestamp", "Run should have auto-generated timestamp")

func test_aggregate_stats():
	manager.record_run({"mode": "easy", "status": "completed", "total_time_seconds": 60.0, "difficulty_breakdown": {"easy": 2, "medium": 0}})
	manager.record_run({"mode": "hard", "status": "failed", "total_time_seconds": 30.0, "difficulty_breakdown": {"easy": 1, "hard": 1}})

	var stats = manager.get_aggregate_stats()
	assert_eq(stats["total_runs"], 2, "Total runs should be 2")
	assert_eq(stats["total_time_spent"], 90.0, "Total time spent should be 90.0")
	assert_eq(stats["avg_run_time"], 45.0, "Average run time should be 45.0")
	assert_eq(stats["clear_rate"], 0.5, "Clear rate should be 50%")
	assert_eq(stats["fastest_run_time"], 60.0, "Fastest run time should be 60.0 since failed runs don't count towards it")
	assert_eq(stats["total_puzzles_by_tier"]["easy"], 3, "Total easy puzzles should be 3")
