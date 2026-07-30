extends RefCounted
class_name NonogramStats

var time_seconds: float = 0.0
var current_level_string: String = ""
var raw_score: int = 0
var stars_earned: int = 0

func _init(_time_seconds: float = 0.0, _level_string: String = "", _score: int = 0, _stars: int = 0):
	time_seconds = _time_seconds
	current_level_string = _level_string
	raw_score = _score
	stars_earned = _stars
