extends RefCounted
class_name DifficultyCurve

## Single source of truth for difficulty thresholds from the GDD.

const EASY_END_DEPTH: int = 10
const MEDIUM_END_DEPTH: int = 30
const MAX_DIMENSION: int = 5


static func get_tier_for_depth(depth: int, mode: String = "endless") -> String:
	var normalized_mode: String = mode.to_lower()
	if normalized_mode == "easy":
		return "easy"
	if normalized_mode == "medium":
		return "medium"
	if normalized_mode == "hard":
		return "hard"
	if depth <= EASY_END_DEPTH:
		return "easy"
	if depth <= MEDIUM_END_DEPTH:
		return "medium"
	return "hard"


static func get_dimensions_for_depth(depth: int) -> Vector3i:
	if depth <= EASY_END_DEPTH:
		return Vector3i(3, 3, 3)
	if depth <= MEDIUM_END_DEPTH:
		return Vector3i(4, 4, 4)
	return Vector3i(5, 5, 5)


static func is_boss_round(depth: int) -> bool:
	return depth > 0 and depth % 10 == 0


static func get_spec(difficulty: String, depth: int) -> Dictionary:
	var tier: String = get_tier_for_depth(depth, difficulty)
	var dimensions: Vector3i = get_dimensions_for_depth(depth)
	return {
		"difficulty": difficulty.to_lower(),
		"depth": maxi(depth, 1),
		"tier": tier,
		"dimensions": dimensions,
		"is_boss": is_boss_round(maxi(depth, 1)),
		"reward_multiplier": 5.0 if is_boss_round(maxi(depth, 1)) else 1.0,
	}
