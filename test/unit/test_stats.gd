extends GutTest

func test_default_initialization():
	var stats = NonogramStats.new()
	assert_eq(stats.time_seconds, 0.0, "Default time_seconds should be 0.0")
	assert_eq(stats.current_level_string, "", "Default current_level_string should be empty")
	assert_eq(stats.raw_score, 0, "Default raw_score should be 0")
	assert_eq(stats.stars_earned, 0, "Default stars_earned should be 0")

func test_custom_initialization():
	var stats = NonogramStats.new(12.5, "level_1", 100, 3)
	assert_eq(stats.time_seconds, 12.5, "time_seconds should match initialized value")
	assert_eq(stats.current_level_string, "level_1", "current_level_string should match initialized value")
	assert_eq(stats.raw_score, 100, "raw_score should match initialized value")
	assert_eq(stats.stars_earned, 3, "stars_earned should match initialized value")

func test_property_modification():
	var stats = NonogramStats.new()
	stats.time_seconds = 45.0
	stats.current_level_string = "level_2"
	stats.raw_score = 500
	stats.stars_earned = 2

	assert_eq(stats.time_seconds, 45.0, "time_seconds should be updatable")
	assert_eq(stats.current_level_string, "level_2", "current_level_string should be updatable")
	assert_eq(stats.raw_score, 500, "raw_score should be updatable")
	assert_eq(stats.stars_earned, 2, "stars_earned should be updatable")
