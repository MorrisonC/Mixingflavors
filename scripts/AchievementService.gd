extends RefCounted
class_name AchievementService

## Durable, deterministic local achievement domain service.
##
## This class intentionally has no scene, clock, file, network, or autoload
## dependency.  The integrating layer owns persistence and emits explicit event
## dictionaries when a game action occurs.  State is a JSON-compatible snapshot
## that can be handed to SaveManager (or another profile store) and loaded back
## into a new service instance.
##
## Event examples:
##   {"type": "round_cleared", "event_id": "run-1:round-1", "depth": 1, "streak": 1, "mistakes": 0}
##   {"type": "run_completed", "run_id": "run-1", "depth": 8, "streak": 4, "mistakes": 0}
## The explicit mistakes field is required for the service to credit a
## no-mistake achievement; an omitted field never implies a perfect run.
##   {"type": "compendium_puzzle_cleared", "puzzle_id": "puzz_001"}
##   {"type": "compendium_completed", "completed_count": 100, "total_count": 100}
##   {"type": "gacha_disclosure_viewed"}
##
## `event_id` is optional.  When supplied, replaying the same ID and payload is
## idempotent; reusing an ID for a different payload is rejected.  A missing
## event_id means each call is a new event, which lets callers record repeated
## identical actions (for example, two depth-1 clears).
##
## The service never writes a timestamp or a random value.  Achievement IDs are
## stable across definition revisions; definition versions are carried beside
## them so progress can be migrated safely.

const STATE_SCHEMA_VERSION: int = 1
const CURRENT_SCHEMA_VERSION: int = STATE_SCHEMA_VERSION
const DEFINITIONS_VERSION: int = 1
const CURRENT_DEFINITIONS_VERSION: int = DEFINITIONS_VERSION
const DEFINITION_VERSION: int = DEFINITIONS_VERSION
const MAX_EVENT_ID_LENGTH: int = 128

## The catalog is data, not presentation.  `unlock_rule` is the machine-readable
## predicate; `unlock_predicate` is retained as a readable data representation.
## No definition uses a gacha outcome, rarity, item drop, or random roll.
const ACHIEVEMENT_DEFINITIONS: Array = [
	{
		"id": "first_round_cleared",
		"version": 1,
		"title": "First Clear",
		"description": "Clear your first gauntlet round.",
		"category": "onboarding",
		"progress_metric": "rounds_cleared",
		"metric": "rounds_cleared",
		"target": 1,
		"unlock_predicate": "rounds_cleared >= 1",
		"unlock_rule": {"metric": "rounds_cleared", "operator": ">=", "target": 1},
		"event_types": ["round_cleared", "boss_round_cleared"],
		"visible": true,
		"luck_dependent": false,
	},
	{
		"id": "ten_rounds_cleared",
		"version": 1,
		"title": "Warmed Up",
		"description": "Clear ten gauntlet rounds.",
		"category": "gauntlet",
		"progress_metric": "rounds_cleared",
		"metric": "rounds_cleared",
		"target": 10,
		"unlock_predicate": "rounds_cleared >= 10",
		"unlock_rule": {"metric": "rounds_cleared", "operator": ">=", "target": 10},
		"event_types": ["round_cleared", "boss_round_cleared"],
		"visible": true,
		"luck_dependent": false,
	},
	{
		"id": "hundred_rounds_cleared",
		"version": 1,
		"title": "Gauntlet Regular",
		"description": "Clear one hundred gauntlet rounds.",
		"category": "gauntlet",
		"progress_metric": "rounds_cleared",
		"metric": "rounds_cleared",
		"target": 100,
		"unlock_predicate": "rounds_cleared >= 100",
		"unlock_rule": {"metric": "rounds_cleared", "operator": ">=", "target": 100},
		"event_types": ["round_cleared", "boss_round_cleared"],
		"visible": true,
		"luck_dependent": false,
	},
	{
		"id": "depth_five",
		"version": 1,
		"title": "Into the Deep",
		"description": "Reach depth five in the gauntlet.",
		"category": "gauntlet",
		"progress_metric": "max_depth",
		"metric": "max_depth",
		"target": 5,
		"unlock_predicate": "max_depth >= 5",
		"unlock_rule": {"metric": "max_depth", "operator": ">=", "target": 5},
		"event_types": ["round_cleared", "run_completed", "boss_round_cleared", "streak_reached", "metric"],
		"visible": true,
		"luck_dependent": false,
	},
	{
		"id": "depth_ten",
		"version": 1,
		"title": "Deep Operator",
		"description": "Reach depth ten in the gauntlet.",
		"category": "gauntlet",
		"progress_metric": "max_depth",
		"metric": "max_depth",
		"target": 10,
		"unlock_predicate": "max_depth >= 10",
		"unlock_rule": {"metric": "max_depth", "operator": ">=", "target": 10},
		"event_types": ["round_cleared", "run_completed", "boss_round_cleared", "streak_reached", "metric"],
		"visible": true,
		"luck_dependent": false,
	},
	{
		"id": "depth_twenty_five",
		"version": 1,
		"title": "Depth Runner",
		"description": "Reach depth twenty-five in the gauntlet.",
		"category": "gauntlet",
		"progress_metric": "max_depth",
		"metric": "max_depth",
		"target": 25,
		"unlock_predicate": "max_depth >= 25",
		"unlock_rule": {"metric": "max_depth", "operator": ">=", "target": 25},
		"event_types": ["round_cleared", "run_completed", "boss_round_cleared", "streak_reached", "metric"],
		"visible": true,
		"luck_dependent": false,
	},
	{
		"id": "streak_five",
		"version": 1,
		"title": "On a Roll",
		"description": "Reach a five-round clear streak.",
		"category": "gauntlet",
		"progress_metric": "best_streak",
		"metric": "best_streak",
		"target": 5,
		"unlock_predicate": "best_streak >= 5",
		"unlock_rule": {"metric": "best_streak", "operator": ">=", "target": 5},
		"event_types": ["round_cleared", "run_completed", "streak_reached", "metric"],
		"visible": true,
		"luck_dependent": false,
	},
	{
		"id": "streak_ten",
		"version": 1,
		"title": "Unbroken Chain",
		"description": "Reach a ten-round clear streak.",
		"category": "gauntlet",
		"progress_metric": "best_streak",
		"metric": "best_streak",
		"target": 10,
		"unlock_predicate": "best_streak >= 10",
		"unlock_rule": {"metric": "best_streak", "operator": ">=", "target": 10},
		"event_types": ["round_cleared", "run_completed", "streak_reached", "metric"],
		"visible": true,
		"luck_dependent": false,
	},
	{
		"id": "flawless_round",
		"version": 1,
		"title": "Clean Solve",
		"description": "Clear a gauntlet round without registering a mistake.",
		"category": "mastery",
		"progress_metric": "no_mistake_wins",
		"metric": "no_mistake_wins",
		"target": 1,
		"unlock_predicate": "no_mistake_wins >= 1",
		"unlock_rule": {"metric": "no_mistake_wins", "operator": ">=", "target": 1},
		"event_types": ["round_cleared", "boss_round_cleared"],
		"visible": true,
		"luck_dependent": false,
	},
	{
		"id": "flawless_run",
		"version": 1,
		"title": "Spotless Operator",
		"description": "Complete a gauntlet run without registering a mistake.",
		"category": "mastery",
		"progress_metric": "no_mistake_run_wins",
		"metric": "no_mistake_run_wins",
		"target": 1,
		"unlock_predicate": "no_mistake_run_wins >= 1",
		"unlock_rule": {"metric": "no_mistake_run_wins", "operator": ">=", "target": 1},
		"event_types": ["run_completed"],
		"visible": true,
		"luck_dependent": false,
	},
	{
		"id": "boss_hunter",
		"version": 1,
		"title": "Boss Breaker",
		"description": "Clear five boss rounds in the gauntlet.",
		"category": "gauntlet",
		"progress_metric": "boss_rounds_cleared",
		"metric": "boss_rounds_cleared",
		"target": 5,
		"unlock_predicate": "boss_rounds_cleared >= 5",
		"unlock_rule": {"metric": "boss_rounds_cleared", "operator": ">=", "target": 5},
		"event_types": ["boss_round_cleared"],
		"visible": true,
		"luck_dependent": false,
	},
	{
		"id": "compendium_explorer",
		"version": 1,
		"title": "Puzzle Cartographer",
		"description": "Clear ten distinct compendium puzzles.",
		"category": "compendium",
		"progress_metric": "compendium_puzzles_cleared",
		"metric": "compendium_puzzles_cleared",
		"target": 10,
		"unlock_predicate": "compendium_puzzles_cleared >= 10",
		"unlock_rule": {"metric": "compendium_puzzles_cleared", "operator": ">=", "target": 10},
		"event_types": ["compendium_puzzle_cleared", "compendium_progress"],
		"visible": true,
		"luck_dependent": false,
	},
	{
		"id": "compendium_scholar",
		"version": 1,
		"title": "Compendium Scholar",
		"description": "Clear fifty distinct compendium puzzles.",
		"category": "compendium",
		"progress_metric": "compendium_puzzles_cleared",
		"metric": "compendium_puzzles_cleared",
		"target": 50,
		"unlock_predicate": "compendium_puzzles_cleared >= 50",
		"unlock_rule": {"metric": "compendium_puzzles_cleared", "operator": ">=", "target": 50},
		"event_types": ["compendium_puzzle_cleared", "compendium_progress"],
		"visible": true,
		"luck_dependent": false,
	},
	{
		"id": "compendium_complete",
		"version": 1,
		"title": "Complete Compendium",
		"description": "Complete every puzzle in the current compendium.",
		"category": "compendium",
		"progress_metric": "compendium_completion",
		"metric": "compendium_completion",
		"target": 1,
		"unlock_predicate": "compendium_completion >= 1",
		"unlock_rule": {"metric": "compendium_completion", "operator": ">=", "target": 1},
		"event_types": ["compendium_completed", "compendium_progress"],
		"visible": true,
		"luck_dependent": false,
	},
	{
		"id": "archive_curator",
		"version": 1,
		"title": "Archive Curator",
		"description": "Visit the Archive three times.",
		"category": "archive",
		"progress_metric": "archive_opened",
		"metric": "archive_opened",
		"target": 3,
		"unlock_predicate": "archive_opened >= 3",
		"unlock_rule": {"metric": "archive_opened", "operator": ">=", "target": 3},
		"event_types": ["archive_opened"],
		"visible": true,
		"luck_dependent": false,
	},
	{
		"id": "archive_disclosure",
		"version": 1,
		"title": "Read the Rules",
		"description": "Open the Archive disclosure panel.",
		"category": "disclosure",
		"progress_metric": "archive_disclosure_actions",
		"metric": "archive_disclosure_actions",
		"target": 1,
		"unlock_predicate": "archive_disclosure_actions >= 1",
		"unlock_rule": {"metric": "archive_disclosure_actions", "operator": ">=", "target": 1},
		"event_types": ["archive_disclosure_viewed"],
		"visible": true,
		"luck_dependent": false,
	},
	{
		"id": "gacha_disclosure",
		"version": 1,
		"title": "Informed Collector",
		"description": "View the gacha rates and disclosure panel; no roll is required.",
		"category": "disclosure",
		"progress_metric": "gacha_disclosure_actions",
		"metric": "gacha_disclosure_actions",
		"target": 1,
		"unlock_predicate": "gacha_disclosure_actions >= 1",
		"unlock_rule": {"metric": "gacha_disclosure_actions", "operator": ">=", "target": 1},
		"event_types": ["gacha_disclosure_viewed", "gacha_rates_viewed", "gacha_receipt_viewed", "disclosure_viewed"],
		"visible": true,
		"luck_dependent": false,
	},
]

const _KNOWN_METRICS: Array = [
	"rounds_cleared",
	"runs_completed",
	"max_depth",
	"best_streak",
	"no_mistake_wins",
	"no_mistake_run_wins",
	"boss_rounds_cleared",
	"compendium_puzzles_cleared",
	"compendium_completion",
	"archive_opened",
	"archive_disclosure_actions",
	"gacha_disclosure_actions",
]

const _METRIC_ALIASES: Dictionary = {
	"rounds": "rounds_cleared",
	"round_clears": "rounds_cleared",
	"run_count": "runs_completed",
	"depth": "max_depth",
	"max_depth_reached": "max_depth",
	"streak": "best_streak",
	"streak_best": "best_streak",
	"mistake_free_rounds": "no_mistake_wins",
	"flawless_rounds": "no_mistake_wins",
	"mistake_free_runs": "no_mistake_run_wins",
	"flawless_runs": "no_mistake_run_wins",
	"boss_clears": "boss_rounds_cleared",
	"compendium_puzzles": "compendium_puzzles_cleared",
	"completed_puzzles": "compendium_puzzles_cleared",
	"compendium_complete": "compendium_completion",
	"archive_visits": "archive_opened",
	"archive_disclosure": "archive_disclosure_actions",
	"gacha_disclosure": "gacha_disclosure_actions",
}

const _EVENT_ALIASES: Dictionary = {
	"round_clear": "round_cleared",
	"round_cleared": "round_cleared",
	"gauntlet_round_cleared": "round_cleared",
	"puzzle_round_cleared": "round_cleared",
	"run_complete": "run_completed",
	"run_completed": "run_completed",
	"run_finished": "run_completed",
	"gauntlet_run_completed": "run_completed",
	"compendium_clear": "compendium_puzzle_cleared",
	"compendium_puzzle_cleared": "compendium_puzzle_cleared",
	"puzzle_cleared": "compendium_puzzle_cleared",
	"compendium_progress": "compendium_progress",
	"compendium_complete": "compendium_completed",
	"compendium_completed": "compendium_completed",
	"archive_open": "archive_opened",
	"archive_opened": "archive_opened",
	"archive_viewed": "archive_opened",
	"archive_disclosure": "archive_disclosure_viewed",
	"archive_disclosure_viewed": "archive_disclosure_viewed",
	"gacha_disclosure": "gacha_disclosure_viewed",
	"gacha_disclosure_viewed": "gacha_disclosure_viewed",
	"gacha_rates_viewed": "gacha_disclosure_viewed",
	"gacha_receipt_viewed": "gacha_disclosure_viewed",
	"disclosure_viewed": "disclosure_viewed",
	"streak_reached": "streak_reached",
	"boss_clear": "boss_round_cleared",
	"boss_cleared": "boss_round_cleared",
	"boss_round_cleared": "boss_round_cleared",
	"metric": "metric",
	"progress": "metric",
}

const _ACHIEVEMENT_ID_ALIASES: Dictionary = {
	"first_clear": "first_round_cleared",
	"rounds_cleared_1": "first_round_cleared",
	"rounds_1": "first_round_cleared",
	"rounds_cleared_10": "ten_rounds_cleared",
	"rounds_10": "ten_rounds_cleared",
	"rounds_cleared_100": "hundred_rounds_cleared",
	"rounds_100": "hundred_rounds_cleared",
	"depth_5": "depth_five",
	"depth_reached_5": "depth_five",
	"depth_10": "depth_ten",
	"depth_reached_10": "depth_ten",
	"depth_25": "depth_twenty_five",
	"depth_reached_25": "depth_twenty_five",
	"streak_5": "streak_five",
	"best_streak_5": "streak_five",
	"streak_10": "streak_ten",
	"best_streak_10": "streak_ten",
	"no_mistake_win": "flawless_round",
	"clean_solve": "flawless_round",
	"no_mistake_run": "flawless_run",
	"boss_5": "boss_hunter",
	"compendium_10": "compendium_explorer",
	"compendium_50": "compendium_scholar",
	"compendium_complete_1": "compendium_complete",
	"archive_3": "archive_curator",
	"gacha_transparency": "gacha_disclosure",
}

const _FORBIDDEN_LUCK_TERMS: Array = [
	"luck",
	"rarity",
	"random_drop",
	"item_drop",
	"gacha_roll",
	"roll_result",
]

# Mutable state is deliberately small and consists only of JSON values.
var _metrics: Dictionary = {}
var _achievements: Dictionary = {}
var _processed_event_ids: Dictionary = {}
var _processed_event_fingerprints: Dictionary = {}
var _compendium_puzzle_ids: Dictionary = {}
var _attempts: int = 0


func _init() -> void:
	_initialize_state()


## Returns an independent snapshot of the versioned definition catalog.
static func get_definitions() -> Array:
	return ACHIEVEMENT_DEFINITIONS.duplicate(true)


static func get_achievement_definitions() -> Array:
	return get_definitions()


static func get_definition_map() -> Dictionary:
	var result: Dictionary = {}
	for definition_value: Variant in ACHIEVEMENT_DEFINITIONS:
		if definition_value is Dictionary:
			var definition: Dictionary = definition_value as Dictionary
			result[str(definition.get("id", ""))] = definition.duplicate(true)
	return result


static func get_achievement_ids() -> Array:
	var result: Array = []
	for definition_value: Variant in ACHIEVEMENT_DEFINITIONS:
		if definition_value is Dictionary:
			result.append(str((definition_value as Dictionary).get("id", "")))
	return result


static func get_definition(achievement_id: Variant) -> Dictionary:
	var id_value: String = _text_value(achievement_id).strip_edges().to_lower()
	var canonical_id: String = str(_ACHIEVEMENT_ID_ALIASES.get(id_value, id_value))
	for definition_value: Variant in ACHIEVEMENT_DEFINITIONS:
		if definition_value is Dictionary and str((definition_value as Dictionary).get("id", "")) == canonical_id:
			return (definition_value as Dictionary).duplicate(true)
	return {}


static func get_achievement(achievement_id: Variant) -> Dictionary:
	return get_definition(achievement_id)


static func get_definition_count() -> int:
	return ACHIEVEMENT_DEFINITIONS.size()


static func is_supported_definition_version(version: Variant) -> bool:
	return _is_integer_value(version) and int(version) >= 0 and int(version) <= DEFINITIONS_VERSION


## Explicitly reports the local-first policy.  Gacha-related progress is limited
## to disclosure actions; rolls, rarity, and item outcomes are not metrics.
static func has_gacha_luck_dependency() -> bool:
	for definition_value: Variant in ACHIEVEMENT_DEFINITIONS:
		if definition_value is Dictionary and not is_luck_independent_definition(definition_value as Dictionary):
			return true
	return false


static func is_luck_independent_definition(definition: Dictionary) -> bool:
	if bool(definition.get("luck_dependent", true)):
		return false
	var metric: String = str(definition.get("progress_metric", "")).to_lower()
	var predicate: String = str(definition.get("unlock_predicate", "")).to_lower()
	for forbidden: Variant in _FORBIDDEN_LUCK_TERMS:
		var term: String = str(forbidden)
		if metric.find(term) >= 0 or predicate.find(term) >= 0:
			return false
	if metric.find("gacha") >= 0 and metric != "gacha_disclosure_actions":
		return false
	return true


static func validate_definition_catalog() -> Dictionary:
	var ids: Dictionary = {}
	for definition_value: Variant in ACHIEVEMENT_DEFINITIONS:
		if not definition_value is Dictionary:
			return _static_failure("INVALID_DEFINITION", "Every achievement definition must be a dictionary.")
		var definition: Dictionary = definition_value as Dictionary
		var id_value: String = str(definition.get("id", ""))
		if id_value.is_empty() or id_value != id_value.strip_edges().to_lower():
			return _static_failure("INVALID_DEFINITION", "Achievement IDs must be canonical, non-empty strings.")
		if ids.has(id_value):
			return _static_failure("DUPLICATE_DEFINITION", "Achievement IDs must be unique: %s" % id_value)
		ids[id_value] = true
		if not _is_integer_value(definition.get("version", null)) or int(definition.get("version", 0)) < 1:
			return _static_failure("INVALID_DEFINITION", "Achievement %s has an invalid version." % id_value)
		if str(definition.get("description", "")).strip_edges().is_empty():
			return _static_failure("INVALID_DEFINITION", "Achievement %s has no description." % id_value)
		if str(definition.get("category", "")).strip_edges().is_empty():
			return _static_failure("INVALID_DEFINITION", "Achievement %s has no category." % id_value)
		var metric_value: Variant = definition.get("progress_metric", definition.get("metric", null))
		if not _is_known_metric(metric_value):
			return _static_failure("INVALID_DEFINITION", "Achievement %s has an unknown progress metric." % id_value)
		var target_value: Variant = definition.get("target", null)
		if not _is_integer_value(target_value) or int(target_value) < 1:
			return _static_failure("INVALID_DEFINITION", "Achievement %s has an invalid target." % id_value)
		if str(definition.get("unlock_predicate", "")).strip_edges().is_empty():
			return _static_failure("INVALID_DEFINITION", "Achievement %s has no unlock predicate." % id_value)
		var unlock_rule: Variant = definition.get("unlock_rule", null)
		if not unlock_rule is Dictionary:
			return _static_failure("INVALID_DEFINITION", "Achievement %s has no machine-readable unlock rule." % id_value)
		var rule: Dictionary = unlock_rule as Dictionary
		if str(rule.get("metric", "")) != str(definition.get("progress_metric", "")) or str(rule.get("operator", "")) != ">=" or not _is_integer_value(rule.get("target", null)) or int(rule.get("target", 0)) != int(definition.get("target", 1)):
			return _static_failure("INVALID_DEFINITION", "Achievement %s has an inconsistent unlock rule." % id_value)
		if not is_luck_independent_definition(definition):
			return _static_failure("LUCK_DEPENDENT_DEFINITION", "Achievement %s depends on random gacha outcomes." % id_value)
	if ids.size() < 10:
		return _static_failure("INSUFFICIENT_DEFINITIONS", "The local catalog must expose at least ten achievements.")
	return {
		"success": true,
		"error": "",
		"error_code": "",
		"message": "",
		"count": ids.size(),
	}


## Processes one explicit event.  Validation and all state changes are
## transactional: malformed or conflicting events leave the current state
## byte-for-byte unchanged.
func process_event(event: Variant) -> Dictionary:
	var normalized_result: Dictionary = _normalize_event(event)
	if not bool(normalized_result.get("ok", false)):
		return _failure_from(normalized_result)
	var normalized: Dictionary = normalized_result.get("event", {}) as Dictionary
	var event_id: String = str(normalized.get("event_id", ""))
	var fingerprint: String = _event_fingerprint(normalized)

	if not event_id.is_empty() and _processed_event_ids.has(event_id):
		var known_fingerprint: String = str(_processed_event_fingerprints.get(event_id, ""))
		if known_fingerprint.is_empty() or known_fingerprint == fingerprint:
			return _event_success(normalized, [], true)
		return _failure("EVENT_ID_CONFLICT", "event_id '%s' was already used for a different event." % event_id)

	var working_metrics: Dictionary = _metrics.duplicate(true)
	var working_puzzle_ids: Dictionary = _compendium_puzzle_ids.duplicate(true)
	var apply_result: Dictionary = _apply_event(normalized, working_metrics, working_puzzle_ids)
	if not bool(apply_result.get("ok", false)):
		return _failure_from(apply_result)
	var touched_metrics: Array = apply_result.get("touched_metrics", []) as Array
	var working_achievements: Dictionary = _achievements.duplicate(true)
	var newly_unlocked: Array = []

	for definition_value: Variant in ACHIEVEMENT_DEFINITIONS:
		if not definition_value is Dictionary:
			return _failure("INVALID_DEFINITION", "Achievement catalog became invalid.")
		var definition: Dictionary = definition_value as Dictionary
		var achievement_id: String = str(definition.get("id", ""))
		var metric: String = str(definition.get("progress_metric", ""))
		var record: Dictionary = working_achievements.get(achievement_id, {}) as Dictionary
		if touched_metrics.has(metric):
			record["attempts"] = int(record.get("attempts", 0)) + 1
		var metric_value: int = int(working_metrics.get(metric, 0))
		record["progress"] = maxi(int(record.get("progress", 0)), metric_value)
		if not bool(record.get("unlocked", false)) and int(record.get("progress", 0)) >= int(definition.get("target", 1)):
			record["unlocked"] = true
			record["unlock_count"] = 1
			newly_unlocked.append(achievement_id)
		working_achievements[achievement_id] = record

	var working_attempts: int = _attempts + 1
	var working_processed_ids: Dictionary = _processed_event_ids.duplicate(true)
	var working_processed_fingerprints: Dictionary = _processed_event_fingerprints.duplicate(true)
	if not event_id.is_empty():
		working_processed_ids[event_id] = true
		working_processed_fingerprints[event_id] = fingerprint

	_metrics = working_metrics
	_achievements = working_achievements
	_compendium_puzzle_ids = working_puzzle_ids
	_attempts = working_attempts
	_processed_event_ids = working_processed_ids
	_processed_event_fingerprints = working_processed_fingerprints
	return _event_success(normalized, newly_unlocked, false)


func record_event(event: Variant) -> Dictionary:
	return process_event(event)


func apply_event(event: Variant) -> Dictionary:
	return process_event(event)


## Returns a deep, JSON-compatible state snapshot.  The returned dictionary is
## disconnected from the service, so callers may safely persist or mutate it.
func get_state() -> Dictionary:
	return {
		"schema_version": STATE_SCHEMA_VERSION,
		"definition_version": DEFINITIONS_VERSION,
		"attempts": _attempts,
		"metrics": _metrics.duplicate(true),
		"achievements": _achievements.duplicate(true),
		"unlocked_ids": get_unlocked_ids(),
		"processed_event_ids": _sorted_processed_event_ids(),
		"event_fingerprints": _sorted_event_fingerprints(),
		"compendium_puzzle_ids": _sorted_compendium_puzzle_ids(),
	}


func get_local_state() -> Dictionary:
	return get_state()


func export_state() -> Dictionary:
	return get_state()


func export_local_state() -> Dictionary:
	return get_state()


func get_metrics() -> Dictionary:
	return _metrics.duplicate(true)


func get_records() -> Dictionary:
	return _achievements.duplicate(true)


func get_progress(achievement_id: Variant) -> int:
	return get_progress_value(achievement_id)


func get_achievement_attempts(achievement_id: Variant) -> int:
	var state: Dictionary = get_achievement_state(achievement_id)
	return int(state.get("attempts", -1)) if not state.is_empty() else -1


func get_achievement_state(achievement_id: Variant) -> Dictionary:
	var definition: Dictionary = get_definition(achievement_id)
	if definition.is_empty():
		return {}
	var id_value: String = str(definition.get("id", ""))
	var result: Dictionary = (_achievements.get(id_value, {}) as Dictionary).duplicate(true)
	result["id"] = id_value
	result["definition_version"] = int(definition.get("version", DEFINITIONS_VERSION))
	result["description"] = str(definition.get("description", ""))
	result["category"] = str(definition.get("category", ""))
	result["progress_metric"] = str(definition.get("progress_metric", ""))
	result["metric"] = str(definition.get("progress_metric", ""))
	result["target"] = int(definition.get("target", 1))
	result["unlock_predicate"] = str(definition.get("unlock_predicate", ""))
	return result


func get_achievement_progress(achievement_id: Variant) -> Dictionary:
	return get_achievement_state(achievement_id)


func get_progress_value(achievement_id: Variant) -> int:
	var state: Dictionary = get_achievement_state(achievement_id)
	return int(state.get("progress", -1)) if not state.is_empty() else -1


func is_unlocked(achievement_id: Variant) -> bool:
	var state: Dictionary = get_achievement_state(achievement_id)
	return bool(state.get("unlocked", false)) if not state.is_empty() else false


func get_unlocked_ids() -> Array:
	var result: Array = []
	for definition_value: Variant in ACHIEVEMENT_DEFINITIONS:
		if not definition_value is Dictionary:
			continue
		var definition: Dictionary = definition_value as Dictionary
		var achievement_id: String = str(definition.get("id", ""))
		var record: Dictionary = _achievements.get(achievement_id, {}) as Dictionary
		if bool(record.get("unlocked", false)):
			result.append(achievement_id)
	return result


## Loads a current snapshot or a supported legacy snapshot.  The new state is
## committed only after every field has been normalized successfully.
func load_state(snapshot: Variant) -> Dictionary:
	if typeof(snapshot) != TYPE_DICTIONARY:
		return _failure("INVALID_STATE", "Achievement state must be a dictionary.")
	var raw: Dictionary = snapshot as Dictionary
	var schema_result: Dictionary = _read_integer_aliases(
		raw,
		["schema_version", "state_version", "version"],
		0,
		false,
		0,
		"INVALID_STATE_SCHEMA"
	)
	if not bool(schema_result.get("ok", false)):
		return _failure_from(schema_result)
	var source_schema_version: int = int(schema_result.get("value", 0))
	if source_schema_version > STATE_SCHEMA_VERSION:
		return _failure("UNSUPPORTED_STATE_SCHEMA", "Achievement state schema %d is newer than this service." % source_schema_version)

	var definition_version_result: Dictionary = _read_optional_nonnegative_integer(raw, "definition_version")
	if not bool(definition_version_result.get("ok", false)):
		return _failure_from(definition_version_result)
	var source_definition_version: int = int(definition_version_result.get("value", 0))
	if source_definition_version > DEFINITIONS_VERSION:
		return _failure("UNSUPPORTED_DEFINITION_VERSION", "Achievement definition version %d is newer than this service." % source_definition_version)

	var working_metrics: Dictionary = _new_metrics()
	var working_achievements: Dictionary = _new_achievement_records()
	var working_processed_ids: Dictionary = {}
	var working_processed_fingerprints: Dictionary = {}
	var working_puzzle_ids: Dictionary = {}
	var progress_overrides: Dictionary = {}
	var unlock_overrides: Dictionary = {}
	var legacy_records: Dictionary = {}

	# Current metric snapshots and the old `progress` map are both accepted.
	var metric_result: Dictionary = _read_dictionary_alias(raw, ["metrics", "metric_values"], "INVALID_STATE_METRICS")
	if not bool(metric_result.get("ok", false)):
		return _failure_from(metric_result)
	if bool(metric_result.get("present", false)):
		var metric_values: Dictionary = metric_result.get("value", {}) as Dictionary
		for raw_metric_key: Variant in metric_values.keys():
			var metric_parse: Dictionary = _parse_stored_metric(raw_metric_key, metric_values.get(raw_metric_key, null), false)
			if not bool(metric_parse.get("ok", false)):
				return _failure_from(metric_parse)
			var metric_name: String = str(metric_parse.get("metric", ""))
			if progress_overrides.has(metric_name):
				return _failure("INVALID_STATE_METRICS", "State contains duplicate metric data for %s." % metric_name)
			progress_overrides[metric_name] = int(metric_parse.get("value", 0))

	var progress_result: Dictionary = _read_dictionary_alias(raw, ["progress"], "INVALID_STATE_PROGRESS")
	if not bool(progress_result.get("ok", false)):
		return _failure_from(progress_result)
	if bool(progress_result.get("present", false)):
		var progress_values: Dictionary = progress_result.get("value", {}) as Dictionary
		for raw_progress_key: Variant in progress_values.keys():
			var raw_progress_value: Variant = progress_values.get(raw_progress_key, null)
			var key_text: String = _text_value(raw_progress_key).strip_edges().to_lower()
			var metric_name: String = _canonical_metric_name(key_text)
			if not metric_name.is_empty():
				var metric_parse: Dictionary = _parse_stored_metric(raw_progress_key, raw_progress_value, false)
				if not bool(metric_parse.get("ok", false)):
					return _failure_from(metric_parse)
				progress_overrides[metric_name] = maxi(int(progress_overrides.get(metric_name, 0)), int(metric_parse.get("value", 0)))
			elif not get_definition(key_text).is_empty():
				var canonical_achievement_id: String = str(get_definition(key_text).get("id", ""))
				if raw_progress_value is Dictionary:
					legacy_records[canonical_achievement_id] = raw_progress_value
				else:
					var record_progress_result: Dictionary = _read_nonnegative_integer_value(raw_progress_value, "INVALID_STATE_PROGRESS")
					if not bool(record_progress_result.get("ok", false)):
						return _failure_from(record_progress_result)
					progress_overrides[canonical_achievement_id] = int(record_progress_result.get("value", 0))
			else:
				return _failure("INVALID_STATE_PROGRESS", "State progress contains an unknown metric or achievement: %s" % key_text)

	# Explicit achievement records are the canonical record format.  `records`
	# is accepted as a migration alias, but two simultaneous sources are not
	# silently merged.
	var record_result: Dictionary = _read_dictionary_alias(raw, ["achievements", "records"], "INVALID_STATE_ACHIEVEMENTS")
	if not bool(record_result.get("ok", false)):
		return _failure_from(record_result)
	var record_values: Dictionary = {}
	if bool(record_result.get("present", false)):
		record_values = (record_result.get("value", {}) as Dictionary).duplicate(true)
	for legacy_id: Variant in legacy_records.keys():
		if record_values.has(legacy_id):
			return _failure("DUPLICATE_STATE_ACHIEVEMENT", "State contains duplicate records for %s." % str(legacy_id))
		record_values[legacy_id] = legacy_records[legacy_id]
	for raw_achievement_id: Variant in record_values.keys():
		var raw_id_text: String = _text_value(raw_achievement_id).strip_edges().to_lower()
		var definition: Dictionary = get_definition(raw_id_text)
		if definition.is_empty() or str(definition.get("id", "")) != raw_id_text:
			return _failure("UNKNOWN_ACHIEVEMENT", "State contains an unknown achievement: %s" % str(raw_achievement_id))
		var normalized_record: Dictionary = _normalize_stored_record(record_values.get(raw_achievement_id, null), definition)
		if not bool(normalized_record.get("ok", false)):
			return _failure_from(normalized_record)
		working_achievements[raw_id_text] = normalized_record.get("record", {}) as Dictionary
		if bool(normalized_record.get("progress_present", false)):
			progress_overrides[raw_id_text] = int(normalized_record.get("progress", 0))

	var unlocked_result: Dictionary = _parse_unlocked_source(raw.get("unlocked", null), raw.has("unlocked"))
	if not bool(unlocked_result.get("ok", false)):
		return _failure_from(unlocked_result)
	for unlocked_id: Variant in (unlocked_result.get("ids", []) as Array):
		unlock_overrides[str(unlocked_id)] = true
	var unlocked_ids_result: Dictionary = _parse_unlocked_source(raw.get("unlocked_ids", null), raw.has("unlocked_ids"))
	if not bool(unlocked_ids_result.get("ok", false)):
		return _failure_from(unlocked_ids_result)
	for unlocked_id: Variant in (unlocked_ids_result.get("ids", []) as Array):
		unlock_overrides[str(unlocked_id)] = true

	var puzzle_ids_result: Dictionary = _read_string_array_alias(raw, ["compendium_puzzle_ids", "completed_puzzle_ids", "completed_puzzles"], "INVALID_STATE_PUZZLES")
	if not bool(puzzle_ids_result.get("ok", false)):
		return _failure_from(puzzle_ids_result)
	var stored_puzzle_ids: Array = puzzle_ids_result.get("value", []) as Array
	for puzzle_id: Variant in stored_puzzle_ids:
		working_puzzle_ids[str(puzzle_id)] = true
	if not stored_puzzle_ids.is_empty():
		progress_overrides["compendium_puzzles_cleared"] = maxi(
			int(progress_overrides.get("compendium_puzzles_cleared", 0)),
			stored_puzzle_ids.size()
		)

	var processed_result: Dictionary = _parse_processed_event_source(raw)
	if not bool(processed_result.get("ok", false)):
		return _failure_from(processed_result)
	working_processed_ids = (processed_result.get("ids", {}) as Dictionary).duplicate(true)
	working_processed_fingerprints = (processed_result.get("fingerprints", {}) as Dictionary).duplicate(true)

	var total_attempts_result: Dictionary = _read_optional_nonnegative_integer(raw, "attempts")
	if not bool(total_attempts_result.get("ok", false)):
		return _failure_from(total_attempts_result)
	var total_attempts: int = int(total_attempts_result.get("value", 0))
	# Preserve safe aggregate metrics even when a legacy catalog did not yet
	# have an achievement definition for them (for example, runs_completed).
	for known_metric: Variant in _KNOWN_METRICS:
		var metric_name: String = str(known_metric)
		if progress_overrides.has(metric_name):
			working_metrics[metric_name] = int(progress_overrides[metric_name])
	var record_attempt_sum: int = 0
	for definition_value: Variant in ACHIEVEMENT_DEFINITIONS:
		var definition: Dictionary = definition_value as Dictionary
		var achievement_id: String = str(definition.get("id", ""))
		var record: Dictionary = working_achievements[achievement_id] as Dictionary
		var metric_name: String = str(definition.get("progress_metric", ""))
		var metric_value: int = int(progress_overrides.get(metric_name, working_metrics.get(metric_name, 0)))
		metric_value = maxi(metric_value, int(record.get("progress", 0)))
		working_metrics[metric_name] = metric_value
		var progress_value: int = int(record.get("progress", 0))
		if progress_overrides.has(achievement_id):
			progress_value = maxi(progress_value, int(progress_overrides[achievement_id]))
		progress_value = maxi(progress_value, metric_value)
		var target_value: int = int(definition.get("target", 1))
		var should_unlock: bool = bool(record.get("unlocked", false)) or unlock_overrides.has(achievement_id) or progress_value >= target_value
		record["progress"] = progress_value
		record["attempts"] = int(record.get("attempts", 0))
		record["unlocked"] = should_unlock
		record["unlock_count"] = 1 if should_unlock else 0
		if should_unlock:
			record["progress"] = maxi(progress_value, target_value)
		working_achievements[achievement_id] = record
		record_attempt_sum += int(record.get("attempts", 0))
	if not bool(total_attempts_result.get("present", false)):
		total_attempts = record_attempt_sum

	# Commit only after all normalization and migration checks have succeeded.
	_metrics = working_metrics
	_achievements = working_achievements
	_processed_event_ids = working_processed_ids
	_processed_event_fingerprints = working_processed_fingerprints
	_compendium_puzzle_ids = working_puzzle_ids
	_attempts = total_attempts

	return {
		"success": true,
		"error": "",
		"error_code": "",
		"message": "",
		"migrated": source_schema_version < STATE_SCHEMA_VERSION or source_definition_version < DEFINITIONS_VERSION,
		"from_schema_version": source_schema_version,
		"from_definition_version": source_definition_version,
		"state": get_state(),
	}


func load_local_state(snapshot: Variant) -> Dictionary:
	return load_state(snapshot)


func reload_state(snapshot: Variant) -> Dictionary:
	return load_state(snapshot)


func reload_local_state(snapshot: Variant) -> Dictionary:
	return load_state(snapshot)


## Reset is intentionally guarded.  Merely constructing/reloading a service,
## or calling reset without the explicit boolean confirmation, cannot erase
## durable progress.
func reset(confirm: Variant = false) -> Dictionary:
	if typeof(confirm) != TYPE_BOOL:
		return _failure("RESET_CONFIRMATION_REQUIRED", "reset requires confirm=true as an explicit request.")
	if not bool(confirm):
		return _failure("RESET_CONFIRMATION_REQUIRED", "reset was not explicitly confirmed; durable progress was preserved.")
	_initialize_state()
	return {
		"success": true,
		"error": "",
		"error_code": "",
		"message": "Achievement progress reset.",
		"reset": true,
		"state": get_state(),
	}


func reset_local_state(confirm: Variant = false) -> Dictionary:
	return reset(confirm)


func reset_state(confirm: Variant = false) -> Dictionary:
	return reset(confirm)


# --- Event normalization ----------------------------------------------------

func _normalize_event(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "error_code": "INVALID_EVENT", "message": "Event must be a dictionary."}
	var raw: Dictionary = value as Dictionary
	var type_result: Dictionary = _read_text_aliases(raw, ["type", "event", "event_type"], true, "INVALID_EVENT_TYPE")
	if not bool(type_result.get("ok", false)):
		return type_result
	var raw_type: String = str(type_result.get("value", ""))
	var event_type: String = str(_EVENT_ALIASES.get(raw_type, ""))
	if event_type.is_empty():
		return {"ok": false, "error_code": "UNKNOWN_EVENT_TYPE", "message": "Unsupported achievement event type: %s" % raw_type}

	var normalized: Dictionary = {
		"type": event_type,
		"event_id": "",
		"amount": 1,
		"has_depth": false,
		"depth": 0,
		"has_streak": false,
		"streak": 0,
		"has_mistakes": false,
		"mistakes": 0,
		"completed": event_type in ["run_completed", "round_cleared", "boss_round_cleared"],
		"has_completed_count": false,
		"completed_count": 0,
		"has_total_count": false,
		"total_count": 0,
		"puzzle_ids": [],
		"has_puzzle_id": false,
		"has_streak_value": false,
		"has_boss": false,
		"boss": false,
		"metric": "",
		"surface": "",
	}

	var event_id_result: Dictionary = _read_event_id_aliases(raw, ["event_id", "eventId"])
	if not bool(event_id_result.get("ok", false)):
		return event_id_result
	var event_id: String = str(event_id_result.get("value", ""))
	normalized["event_id"] = event_id

	var amount_result: Dictionary = _read_integer_aliases(raw, ["amount", "count", "increment", "delta"], 1, false, 1, "INVALID_AMOUNT")
	if not bool(amount_result.get("ok", false)):
		return amount_result
	var amount_value: int = int(amount_result.get("value", 1))

	var value_result: Dictionary = _read_optional_nonnegative_integer(raw, "value")
	if not bool(value_result.get("ok", false)):
		return value_result
	if event_type == "streak_reached":
		var streak_value_result: Dictionary = _read_integer_aliases(raw, ["streak", "best_streak", "value"], 0, true, 0, "INVALID_STREAK")
		if not bool(streak_value_result.get("ok", false)):
			return streak_value_result
		normalized["has_streak"] = true
		normalized["streak"] = int(streak_value_result.get("value", 0))
		normalized["has_streak_value"] = true
	elif event_type == "metric":
		if not bool(value_result.get("present", false)) and not bool(amount_result.get("present", false)):
			return {"ok": false, "error_code": "INVALID_AMOUNT", "message": "A metric event requires amount or value."}
		if bool(value_result.get("present", false)) and int(value_result.get("value", 0)) < 1:
			return {"ok": false, "error_code": "INVALID_AMOUNT", "message": "A metric value must be a positive integer."}
		if bool(value_result.get("present", false)) and bool(amount_result.get("present", false)) and int(value_result.get("value", 0)) != amount_value:
			return {"ok": false, "error_code": "INVALID_AMOUNT", "message": "Metric amount and value aliases disagree."}
		if not bool(amount_result.get("present", false)):
			amount_value = int(value_result.get("value", 1))
	elif bool(value_result.get("present", false)) and not bool(amount_result.get("present", false)) and event_type in ["round_cleared", "boss_round_cleared", "run_completed", "compendium_puzzle_cleared", "compendium_progress", "metric"]:
		# A compact `value` is accepted as a count for action events.
		amount_value = maxi(1, int(value_result.get("value", 1)))
	normalized["amount"] = amount_value

	var depth_result: Dictionary = _read_integer_aliases(raw, ["depth", "round_depth", "reached_depth"], 1, false, 0, "INVALID_DEPTH")
	if not bool(depth_result.get("ok", false)):
		return depth_result
	if bool(depth_result.get("present", false)):
		normalized["has_depth"] = true
		normalized["depth"] = int(depth_result.get("value", 0))

	var streak_result: Dictionary = _read_integer_aliases(raw, ["streak", "best_streak", "streak_count"], 0, false, 0, "INVALID_STREAK")
	if not bool(streak_result.get("ok", false)):
		return streak_result
	if bool(streak_result.get("present", false)) and not bool(normalized.get("has_streak", false)):
		normalized["has_streak"] = true
		normalized["streak"] = int(streak_result.get("value", 0))

	var mistakes_result: Dictionary = _read_integer_aliases(raw, ["mistakes", "mistake_count"], 0, false, 0, "INVALID_MISTAKES")
	if not bool(mistakes_result.get("ok", false)):
		return mistakes_result
	if bool(mistakes_result.get("present", false)):
		normalized["has_mistakes"] = true
		normalized["mistakes"] = int(mistakes_result.get("value", 0))

	var completed_result: Dictionary = _read_optional_bool(raw, "completed")
	if not bool(completed_result.get("ok", false)):
		return completed_result
	if bool(completed_result.get("present", false)):
		normalized["completed"] = bool(completed_result.get("value", false))
	if event_type == "round_cleared" or event_type == "boss_round_cleared":
		if not bool(normalized.get("completed", true)):
			return {"ok": false, "error_code": "INVALID_EVENT", "message": "A round-clear event cannot set completed=false."}

	var total_count_result: Dictionary = _read_optional_integer(raw, "total_count", 1)
	if not bool(total_count_result.get("ok", false)):
		return total_count_result
	var total_count_alias: Dictionary = _read_optional_integer(raw, "total_puzzles", 1)
	if not bool(total_count_alias.get("ok", false)):
		return total_count_alias
	if bool(total_count_result.get("present", false)) and bool(total_count_alias.get("present", false)) and int(total_count_result.get("value", 0)) != int(total_count_alias.get("value", 0)):
		return {"ok": false, "error_code": "INVALID_COUNT", "message": "total_count aliases disagree."}
	if bool(total_count_alias.get("present", false)):
		normalized["has_total_count"] = true
		normalized["total_count"] = int(total_count_alias.get("value", 0))
	elif bool(total_count_result.get("present", false)):
		normalized["has_total_count"] = true
		normalized["total_count"] = int(total_count_result.get("value", 0))

	var completed_count_result: Dictionary = _read_optional_integer(raw, "completed_count", 0)
	if not bool(completed_count_result.get("ok", false)):
		return completed_count_result
	var completed_count_alias: Dictionary = _read_optional_integer(raw, "completed_puzzles", 0)
	if not bool(completed_count_alias.get("ok", false)):
		return completed_count_alias
	if bool(completed_count_result.get("present", false)) and bool(completed_count_alias.get("present", false)) and int(completed_count_result.get("value", 0)) != int(completed_count_alias.get("value", 0)):
		return {"ok": false, "error_code": "INVALID_COUNT", "message": "completed_count aliases disagree."}
	if bool(completed_count_alias.get("present", false)):
		normalized["has_completed_count"] = true
		normalized["completed_count"] = int(completed_count_alias.get("value", 0))
	elif bool(completed_count_result.get("present", false)):
		normalized["has_completed_count"] = true
		normalized["completed_count"] = int(completed_count_result.get("value", 0))

	var puzzle_id_result: Dictionary = _read_optional_text(raw, "puzzle_id")
	if not bool(puzzle_id_result.get("ok", false)):
		return puzzle_id_result
	if bool(puzzle_id_result.get("present", false)):
		normalized["has_puzzle_id"] = true
		normalized["puzzle_ids"] = [str(puzzle_id_result.get("value", ""))]
	var puzzle_ids_result: Dictionary = _read_optional_string_array(raw, "puzzle_ids")
	if not bool(puzzle_ids_result.get("ok", false)):
		return puzzle_ids_result
	if bool(puzzle_ids_result.get("present", false)):
		var supplied_ids: Array = puzzle_ids_result.get("value", []) as Array
		if bool(normalized.get("has_puzzle_id", false)):
			for supplied_id: Variant in supplied_ids:
				if str(supplied_id) != str((normalized["puzzle_ids"] as Array)[0]):
					return {"ok": false, "error_code": "INVALID_PUZZLE_ID", "message": "puzzle_id and puzzle_ids disagree."}
		else:
			normalized["puzzle_ids"] = supplied_ids.duplicate()
			normalized["has_puzzle_id"] = not supplied_ids.is_empty()

	var boss_result: Dictionary = _read_optional_bool(raw, "boss")
	if not bool(boss_result.get("ok", false)):
		return boss_result
	if bool(boss_result.get("present", false)):
		normalized["has_boss"] = true
		normalized["boss"] = bool(boss_result.get("value", false))

	var surface_result: Dictionary = _read_optional_text(raw, "surface")
	if not bool(surface_result.get("ok", false)):
		return surface_result
	if bool(surface_result.get("present", false)):
		normalized["surface"] = str(surface_result.get("value", "")).strip_edges().to_lower()

	if event_type == "metric":
		var metric_result: Dictionary = _read_text_aliases(raw, ["metric", "progress_metric"], true, "INVALID_METRIC")
		if not bool(metric_result.get("ok", false)):
			return metric_result
		var metric_name: String = _canonical_metric_name(str(metric_result.get("value", "")))
		if not _is_known_metric(metric_name):
			return {"ok": false, "error_code": "INVALID_METRIC", "message": "Metric events may only use local, non-luck metrics."}
		normalized["metric"] = metric_name
	elif raw.has("metric") or raw.has("progress_metric"):
		return {"ok": false, "error_code": "INVALID_EVENT", "message": "A metric is only valid on a metric event."}

	if event_type == "compendium_completed":
		if not bool(normalized.get("completed", false)) and not (bool(normalized.get("has_completed_count", false)) and bool(normalized.get("has_total_count", false))):
			return {"ok": false, "error_code": "INVALID_EVENT", "message": "A completion event requires completed=true or both completed_count and total_count."}

	if event_type == "streak_reached" and not bool(normalized.get("has_streak", false)):
		return {"ok": false, "error_code": "INVALID_STREAK", "message": "A streak event requires a streak value."}

	if event_type == "disclosure_viewed" and normalized.get("surface", "") not in ["archive", "gacha"]:
		return {"ok": false, "error_code": "INVALID_EVENT", "message": "disclosure_viewed requires surface='archive' or surface='gacha'."}

	return {"ok": true, "event": normalized}


func _apply_event(event: Dictionary, metrics: Dictionary, puzzle_ids: Dictionary) -> Dictionary:
	var event_type: String = str(event.get("type", ""))
	var amount: int = maxi(1, int(event.get("amount", 1)))
	var touched: Array = []
	match event_type:
		"round_cleared", "boss_round_cleared":
			_add_metric(metrics, "rounds_cleared", amount)
			_touch_metric(touched, "rounds_cleared")
			if bool(event.get("has_depth", false)):
				_raise_metric(metrics, "max_depth", int(event.get("depth", 0)))
				_touch_metric(touched, "max_depth")
			if bool(event.get("has_streak", false)):
				_raise_metric(metrics, "best_streak", int(event.get("streak", 0)))
				_touch_metric(touched, "best_streak")
			if bool(event.get("has_mistakes", false)) and int(event.get("mistakes", 0)) == 0:
				_add_metric(metrics, "no_mistake_wins", amount)
				_touch_metric(touched, "no_mistake_wins")
			if event_type == "boss_round_cleared" or bool(event.get("boss", false)):
				_add_metric(metrics, "boss_rounds_cleared", amount)
				_touch_metric(touched, "boss_rounds_cleared")
		"run_completed":
			if bool(event.get("completed", true)):
				_add_metric(metrics, "runs_completed", amount)
				_touch_metric(touched, "runs_completed")
				if bool(event.get("has_mistakes", false)) and int(event.get("mistakes", 0)) == 0:
					_add_metric(metrics, "no_mistake_run_wins", amount)
					_touch_metric(touched, "no_mistake_run_wins")
			if bool(event.get("has_depth", false)):
				_raise_metric(metrics, "max_depth", int(event.get("depth", 0)))
				_touch_metric(touched, "max_depth")
			if bool(event.get("has_streak", false)):
				_raise_metric(metrics, "best_streak", int(event.get("streak", 0)))
				_touch_metric(touched, "best_streak")
		"streak_reached":
			_raise_metric(metrics, "best_streak", int(event.get("streak", 0)))
			_touch_metric(touched, "best_streak")
		"compendium_puzzle_cleared", "compendium_progress":
			var supplied_ids: Array = event.get("puzzle_ids", []) as Array
			if not supplied_ids.is_empty():
				for puzzle_id: Variant in supplied_ids:
					if not puzzle_ids.has(str(puzzle_id)):
						puzzle_ids[str(puzzle_id)] = true
				_raise_metric(metrics, "compendium_puzzles_cleared", puzzle_ids.size())
			elif bool(event.get("has_completed_count", false)):
				_raise_metric(metrics, "compendium_puzzles_cleared", int(event.get("completed_count", 0)))
			else:
				_add_metric(metrics, "compendium_puzzles_cleared", amount)
			_touch_metric(touched, "compendium_puzzles_cleared")
			if bool(event.get("has_total_count", false)) and bool(event.get("has_completed_count", false)) and int(event.get("completed_count", 0)) >= int(event.get("total_count", 1)):
				_raise_metric(metrics, "compendium_completion", 1)
				_touch_metric(touched, "compendium_completion")
		"compendium_completed":
			if bool(event.get("has_completed_count", false)):
				_raise_metric(metrics, "compendium_puzzles_cleared", int(event.get("completed_count", 0)))
				_touch_metric(touched, "compendium_puzzles_cleared")
			if bool(event.get("completed", false)):
				_raise_metric(metrics, "compendium_completion", 1)
			elif bool(event.get("has_completed_count", false)) and bool(event.get("has_total_count", false)) and int(event.get("completed_count", 0)) >= int(event.get("total_count", 1)):
				_raise_metric(metrics, "compendium_completion", 1)
			_touch_metric(touched, "compendium_completion")
		"archive_opened":
			_add_metric(metrics, "archive_opened", amount)
			_touch_metric(touched, "archive_opened")
		"archive_disclosure_viewed":
			_add_metric(metrics, "archive_disclosure_actions", amount)
			_touch_metric(touched, "archive_disclosure_actions")
		"gacha_disclosure_viewed":
			_add_metric(metrics, "gacha_disclosure_actions", amount)
			_touch_metric(touched, "gacha_disclosure_actions")
		"disclosure_viewed":
			if str(event.get("surface", "")) == "archive":
				_add_metric(metrics, "archive_disclosure_actions", amount)
				_touch_metric(touched, "archive_disclosure_actions")
			elif str(event.get("surface", "")) == "gacha":
				_add_metric(metrics, "gacha_disclosure_actions", amount)
				_touch_metric(touched, "gacha_disclosure_actions")
		"metric":
			var metric: String = str(event.get("metric", ""))
			if metric in ["max_depth", "best_streak", "compendium_puzzles_cleared", "compendium_completion"]:
				_raise_metric(metrics, metric, amount)
			else:
				_add_metric(metrics, metric, amount)
			_touch_metric(touched, metric)
		_:
			return {"ok": false, "error_code": "UNKNOWN_EVENT_TYPE", "message": "Unsupported achievement event type: %s" % event_type}
	return {"ok": true, "touched_metrics": touched}


# --- State normalization ----------------------------------------------------

func _normalize_stored_record(value: Variant, definition: Dictionary) -> Dictionary:
	var achievement_id: String = str(definition.get("id", ""))
	var record: Dictionary = {
		"id": achievement_id,
		"definition_version": int(definition.get("version", DEFINITIONS_VERSION)),
		"attempts": 0,
		"progress": 0,
		"unlocked": false,
		"unlock_count": 0,
	}
	var progress_present: bool = false
	if value is Dictionary:
		var raw: Dictionary = value as Dictionary
		if raw.has("id") and str(raw.get("id", "")) != achievement_id:
			return {"ok": false, "error_code": "INVALID_STATE_RECORD", "message": "Achievement record ID does not match its key."}
		if raw.has("achievement_id") and str(raw.get("achievement_id", "")) != achievement_id:
			return {"ok": false, "error_code": "INVALID_STATE_RECORD", "message": "Achievement record identity does not match its key."}
		if raw.has("metric") and _canonical_metric_name(str(raw.get("metric", ""))) != str(definition.get("progress_metric", "")):
			return {"ok": false, "error_code": "INVALID_STATE_RECORD", "message": "Achievement record metric does not match its definition."}
		if raw.has("progress_metric") and _canonical_metric_name(str(raw.get("progress_metric", ""))) != str(definition.get("progress_metric", "")):
			return {"ok": false, "error_code": "INVALID_STATE_RECORD", "message": "Achievement record progress metric does not match its definition."}
		if raw.has("definition_version") and (not _is_integer_value(raw.get("definition_version", null)) or int(raw.get("definition_version", 0)) > DEFINITIONS_VERSION):
			return {"ok": false, "error_code": "INVALID_STATE_RECORD", "message": "Achievement record has an invalid definition version."}
		if raw.has("version") and (not _is_integer_value(raw.get("version", null)) or int(raw.get("version", 0)) > DEFINITIONS_VERSION):
			return {"ok": false, "error_code": "INVALID_STATE_RECORD", "message": "Achievement record has an invalid version."}
		var attempts_result: Dictionary = _read_optional_nonnegative_integer_from(raw, ["attempts", "attempt_count"], "INVALID_STATE_RECORD")
		if not bool(attempts_result.get("ok", false)):
			return attempts_result
		record["attempts"] = int(attempts_result.get("value", 0))
		var progress_result: Dictionary = _read_optional_nonnegative_integer_from(raw, ["progress", "value", "current"], "INVALID_STATE_RECORD")
		if not bool(progress_result.get("ok", false)):
			return progress_result
		if bool(progress_result.get("present", false)):
			record["progress"] = int(progress_result.get("value", 0))
			progress_present = true
		var unlocked_result: Dictionary = _read_optional_bool_from(raw, ["unlocked", "is_unlocked"], "INVALID_STATE_RECORD")
		if not bool(unlocked_result.get("ok", false)):
			return unlocked_result
		if bool(unlocked_result.get("present", false)):
			record["unlocked"] = bool(unlocked_result.get("value", false))
		var unlock_count_result: Dictionary = _read_optional_nonnegative_integer_from(raw, ["unlock_count"], "INVALID_STATE_RECORD")
		if not bool(unlock_count_result.get("ok", false)):
			return unlock_count_result
		if bool(unlock_count_result.get("present", false)) and int(unlock_count_result.get("value", 0)) > 1:
			return {"ok": false, "error_code": "INVALID_STATE_RECORD", "message": "unlock_count cannot exceed one."}
		if int(unlock_count_result.get("value", 0)) > 0:
			record["unlocked"] = true
			record["unlock_count"] = 1
		if raw.has("target") and (not _is_integer_value(raw.get("target", null)) or int(raw.get("target", 0)) != int(definition.get("target", 1))):
			return {"ok": false, "error_code": "INVALID_STATE_RECORD", "message": "Achievement record target does not match its definition."}
	elif typeof(value) == TYPE_BOOL:
		record["unlocked"] = bool(value)
		progress_present = true
	elif _is_integer_value(value):
		record["progress"] = int(value)
		progress_present = true
	else:
		return {"ok": false, "error_code": "INVALID_STATE_RECORD", "message": "Achievement record must be a dictionary, boolean, or integer progress value."}
	return {"ok": true, "record": record, "progress_present": progress_present}


func _parse_processed_event_source(raw: Dictionary) -> Dictionary:
	var ids: Dictionary = {}
	var fingerprints: Dictionary = {}
	var list_result: Dictionary = _read_optional_string_array(raw, "processed_event_ids")
	if not bool(list_result.get("ok", false)):
		return list_result
	if bool(list_result.get("present", false)):
		for event_id: Variant in (list_result.get("value", []) as Array):
			if ids.has(str(event_id)):
				return {"ok": false, "error_code": "INVALID_STATE_EVENTS", "message": "processed_event_ids contains a duplicate."}
			ids[str(event_id)] = true

	var map_result: Dictionary = _read_optional_dictionary(raw, "event_fingerprints")
	if not bool(map_result.get("ok", false)):
		return map_result
	if bool(map_result.get("present", false)):
		var fingerprint_values: Dictionary = map_result.get("value", {}) as Dictionary
		for raw_event_id: Variant in fingerprint_values.keys():
			var event_id: String = str(raw_event_id)
			var fingerprint_value: Variant = fingerprint_values.get(raw_event_id, null)
			if event_id.is_empty() or event_id.length() > MAX_EVENT_ID_LENGTH or event_id != event_id.strip_edges() or typeof(fingerprint_value) != TYPE_STRING or str(fingerprint_value).is_empty():
				return {"ok": false, "error_code": "INVALID_STATE_EVENTS", "message": "event_fingerprints contains an invalid entry."}
			ids[event_id] = true
			fingerprints[event_id] = str(fingerprint_value)

	var legacy_map_result: Dictionary = _read_optional_dictionary(raw, "processed_events")
	if not bool(legacy_map_result.get("ok", false)):
		return legacy_map_result
	if bool(legacy_map_result.get("present", false)):
		var legacy_values: Dictionary = legacy_map_result.get("value", {}) as Dictionary
		for raw_event_id: Variant in legacy_values.keys():
			var event_id: String = str(raw_event_id)
			var fingerprint_value: Variant = legacy_values.get(raw_event_id, null)
			if event_id.is_empty() or event_id.length() > MAX_EVENT_ID_LENGTH or event_id != event_id.strip_edges() or typeof(fingerprint_value) != TYPE_STRING or str(fingerprint_value).is_empty():
				return {"ok": false, "error_code": "INVALID_STATE_EVENTS", "message": "processed_events contains an invalid entry."}
			ids[event_id] = true
			fingerprints[event_id] = str(fingerprint_value)
	return {"ok": true, "ids": ids, "fingerprints": fingerprints}


func _parse_unlocked_source(value: Variant, present: bool) -> Dictionary:
	if not present:
		return {"ok": true, "ids": []}
	var ids: Array = []
	if typeof(value) == TYPE_ARRAY:
		for raw_id: Variant in (value as Array):
			var id_value: String = _text_value(raw_id).strip_edges().to_lower()
			if id_value.is_empty() or get_definition(id_value).is_empty() or str(get_definition(id_value).get("id", "")) != id_value:
				return {"ok": false, "error_code": "INVALID_STATE_UNLOCKS", "message": "Unlocked state contains an unknown achievement: %s" % str(raw_id)}
			ids.append(id_value)
	elif value is Dictionary:
		for raw_id: Variant in (value as Dictionary).keys():
			var id_value: String = _text_value(raw_id).strip_edges().to_lower()
			if id_value.is_empty() or get_definition(id_value).is_empty() or str(get_definition(id_value).get("id", "")) != id_value:
				return {"ok": false, "error_code": "INVALID_STATE_UNLOCKS", "message": "Unlocked state contains an unknown achievement: %s" % str(raw_id)}
			var unlocked_value: Variant = (value as Dictionary).get(raw_id, false)
			if typeof(unlocked_value) != TYPE_BOOL:
				return {"ok": false, "error_code": "INVALID_STATE_UNLOCKS", "message": "Unlocked state values must be booleans."}
			if bool(unlocked_value):
				ids.append(id_value)
	else:
		return {"ok": false, "error_code": "INVALID_STATE_UNLOCKS", "message": "Unlocked state must be an array or dictionary."}
	return {"ok": true, "ids": ids}


# --- Generic validation and conversion helpers ------------------------------

func _read_event_id_aliases(raw: Dictionary, keys: Array) -> Dictionary:
	var found: bool = false
	var selected: String = ""
	for key: Variant in keys:
		if not raw.has(key):
			continue
		var value: Variant = raw.get(key, null)
		if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
			return {"ok": false, "error_code": "INVALID_EVENT_ID", "message": "Event field %s must be a string." % str(key)}
		var text_value: String = str(value)
		if found and selected != text_value:
			return {"ok": false, "error_code": "INVALID_EVENT_ID", "message": "Event ID aliases disagree."}
		found = true
		selected = text_value
	if found and (selected.is_empty() or selected.length() > MAX_EVENT_ID_LENGTH or selected != selected.strip_edges()):
		return {"ok": false, "error_code": "INVALID_EVENT_ID", "message": "event_id must be a non-empty canonical string no longer than %d characters." % MAX_EVENT_ID_LENGTH}
	return {"ok": true, "present": found, "value": selected}


func _read_text_aliases(raw: Dictionary, keys: Array, required: bool, error_code: String) -> Dictionary:
	var found: bool = false
	var selected: String = ""
	for key: Variant in keys:
		if not raw.has(key):
			continue
		var value: Variant = raw.get(key, null)
		if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
			return {"ok": false, "error_code": error_code, "message": "Event field %s must be a string." % str(key)}
		var text_value: String = str(value)
		if found and selected != text_value:
			return {"ok": false, "error_code": error_code, "message": "Event field aliases disagree: %s." % str(key)}
		found = true
		selected = text_value
	if required and not found:
		return {"ok": false, "error_code": error_code, "message": "Event field type is required."}
	if not selected.strip_edges().is_empty() and selected != selected.strip_edges().to_lower():
		return {"ok": false, "error_code": error_code, "message": "Event field %s must be canonical lowercase text." % str(keys[0])}
	return {"ok": true, "present": found, "value": selected.strip_edges().to_lower()}


func _read_optional_text(raw: Dictionary, key: String) -> Dictionary:
	if not raw.has(key):
		return {"ok": true, "present": false, "value": ""}
	var value: Variant = raw.get(key, null)
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return {"ok": false, "error_code": "INVALID_EVENT", "message": "Event field %s must be a string." % key}
	var text_value: String = str(value)
	if text_value.is_empty() or text_value != text_value.strip_edges():
		return {"ok": false, "error_code": "INVALID_EVENT", "message": "Event field %s must be a non-empty canonical string." % key}
	return {"ok": true, "present": true, "value": text_value}


func _read_integer_aliases(raw: Dictionary, keys: Array, minimum: int, required: bool, default_value: int, error_code: String) -> Dictionary:
	var found: bool = false
	var selected: int = default_value
	for key: Variant in keys:
		if not raw.has(key):
			continue
		var parsed: Dictionary = _read_nonnegative_integer_value(raw.get(key, null), error_code)
		if not bool(parsed.get("ok", false)):
			return parsed
		var value: int = int(parsed.get("value", 0))
		if value < minimum:
			return {"ok": false, "error_code": error_code, "message": "Event numeric field %s is outside its allowed range." % str(key)}
		if found and selected != value:
			return {"ok": false, "error_code": error_code, "message": "Event numeric aliases disagree: %s." % str(key)}
		found = true
		selected = value
	if required and not found:
		return {"ok": false, "error_code": error_code, "message": "Event numeric field is required."}
	return {"ok": true, "present": found, "value": selected}


func _read_optional_nonnegative_integer(raw: Dictionary, key: String) -> Dictionary:
	if not raw.has(key):
		return {"ok": true, "present": false, "value": 0}
	var parsed: Dictionary = _read_nonnegative_integer_value(raw.get(key, null), "INVALID_NUMBER")
	if not bool(parsed.get("ok", false)):
		return parsed
	parsed["present"] = true
	return parsed


func _read_nonnegative_integer_value(value: Variant, error_code: String) -> Dictionary:
	if not _is_integer_value(value):
		return {"ok": false, "error_code": error_code, "message": "Expected a non-negative integer."}
	if int(value) < 0:
		return {"ok": false, "error_code": error_code, "message": "Expected a non-negative integer."}
	return {"ok": true, "value": int(value)}


func _read_optional_integer(raw: Dictionary, key: String, minimum: int) -> Dictionary:
	if not raw.has(key):
		return {"ok": true, "present": false, "value": 0}
	var parsed: Dictionary = _read_nonnegative_integer_value(raw.get(key, null), "INVALID_NUMBER")
	if not bool(parsed.get("ok", false)):
		return parsed
	if int(parsed.get("value", 0)) < minimum:
		return {"ok": false, "error_code": "INVALID_COUNT", "message": "Event field %s is outside its allowed range." % key}
	return {"ok": true, "present": true, "value": int(parsed.get("value", 0))}


func _read_optional_bool(raw: Dictionary, key: String) -> Dictionary:
	if not raw.has(key):
		return {"ok": true, "present": false, "value": false}
	var value: Variant = raw.get(key, null)
	if typeof(value) != TYPE_BOOL:
		return {"ok": false, "error_code": "INVALID_EVENT", "message": "Event field %s must be a boolean." % key}
	return {"ok": true, "present": true, "value": value}


func _read_optional_string_array(raw: Dictionary, key: String) -> Dictionary:
	if not raw.has(key):
		return {"ok": true, "present": false, "value": []}
	var value: Variant = raw.get(key, null)
	if typeof(value) != TYPE_ARRAY:
		return {"ok": false, "error_code": "INVALID_PUZZLE_ID", "message": "Event field %s must be an array of puzzle IDs." % key}
	var result: Array = []
	for raw_id: Variant in (value as Array):
		var id_value: String = _text_value(raw_id)
		if id_value.is_empty() or id_value != id_value.strip_edges():
			return {"ok": false, "error_code": "INVALID_PUZZLE_ID", "message": "Puzzle IDs must be non-empty canonical strings."}
		if result.has(id_value):
			return {"ok": false, "error_code": "INVALID_PUZZLE_ID", "message": "Puzzle IDs must be unique within an event."}
		result.append(id_value)
	return {"ok": true, "present": true, "value": result}


func _read_dictionary_alias(raw: Dictionary, keys: Array, error_code: String) -> Dictionary:
	var found: bool = false
	var selected: Dictionary = {}
	for key: Variant in keys:
		if not raw.has(key):
			continue
		var value: Variant = raw.get(key, null)
		if typeof(value) != TYPE_DICTIONARY:
			return {"ok": false, "error_code": error_code, "message": "State field %s must be a dictionary." % str(key)}
		if found and selected != value:
			return {"ok": false, "error_code": error_code, "message": "State dictionary aliases disagree: %s." % str(key)}
		found = true
		selected = value as Dictionary
	return {"ok": true, "present": found, "value": selected}


func _read_optional_dictionary(raw: Dictionary, key: String) -> Dictionary:
	if not raw.has(key):
		return {"ok": true, "present": false, "value": {}}
	var value: Variant = raw.get(key, null)
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "error_code": "INVALID_STATE", "message": "State field %s must be a dictionary." % key}
	return {"ok": true, "present": true, "value": value as Dictionary}


func _read_optional_nonnegative_integer_from(raw: Dictionary, keys: Array, error_code: String) -> Dictionary:
	return _read_integer_aliases(raw, keys, 0, false, 0, error_code)


func _read_optional_bool_from(raw: Dictionary, keys: Array, error_code: String) -> Dictionary:
	var found: bool = false
	var selected: bool = false
	for key: Variant in keys:
		if not raw.has(key):
			continue
		var value: Variant = raw.get(key, null)
		if typeof(value) != TYPE_BOOL:
			return {"ok": false, "error_code": error_code, "message": "State field %s must be a boolean." % str(key)}
		if found and selected != bool(value):
			return {"ok": false, "error_code": error_code, "message": "State boolean aliases disagree: %s." % str(key)}
		found = true
		selected = bool(value)
	return {"ok": true, "present": found, "value": selected}


func _read_string_array_alias(raw: Dictionary, keys: Array, error_code: String) -> Dictionary:
	var found: bool = false
	var selected: Array = []
	for key: Variant in keys:
		if not raw.has(key):
			continue
		var value: Variant = raw.get(key, null)
		if typeof(value) != TYPE_ARRAY:
			return {"ok": false, "error_code": error_code, "message": "State field %s must be an array." % str(key)}
		var parsed: Array = []
		for raw_id: Variant in (value as Array):
			var id_value: String = _text_value(raw_id)
			if id_value.is_empty() or id_value != id_value.strip_edges():
				return {"ok": false, "error_code": error_code, "message": "State contains an invalid string ID."}
			if parsed.has(id_value):
				return {"ok": false, "error_code": error_code, "message": "State contains duplicate string IDs."}
			parsed.append(id_value)
		if found and selected != parsed:
			return {"ok": false, "error_code": error_code, "message": "State string-array aliases disagree: %s." % str(key)}
		found = true
		selected = parsed
	return {"ok": true, "present": found, "value": selected}


func _parse_stored_metric(raw_key: Variant, value: Variant, allow_achievement_id: bool) -> Dictionary:
	var key_text: String = _text_value(raw_key).strip_edges().to_lower()
	var metric_name: String = _canonical_metric_name(key_text)
	if metric_name.is_empty() and allow_achievement_id and not get_definition(key_text).is_empty():
		metric_name = str(get_definition(key_text).get("progress_metric", ""))
	if not _is_known_metric(metric_name):
		return {"ok": false, "error_code": "INVALID_STATE_METRICS", "message": "State metric is unknown: %s" % str(raw_key)}
	var parsed: Dictionary = _read_nonnegative_integer_value(value, "INVALID_STATE_METRICS")
	if not bool(parsed.get("ok", false)):
		return parsed
	return {"ok": true, "metric": metric_name, "value": int(parsed.get("value", 0))}


# --- State/event utility helpers -------------------------------------------

func _initialize_state() -> void:
	_metrics = _new_metrics()
	_achievements = _new_achievement_records()
	_processed_event_ids = {}
	_processed_event_fingerprints = {}
	_compendium_puzzle_ids = {}
	_attempts = 0


func _new_metrics() -> Dictionary:
	var result: Dictionary = {}
	for metric: Variant in _KNOWN_METRICS:
		result[str(metric)] = 0
	return result


func _new_achievement_records() -> Dictionary:
	var result: Dictionary = {}
	for definition_value: Variant in ACHIEVEMENT_DEFINITIONS:
		if not definition_value is Dictionary:
			continue
		var definition: Dictionary = definition_value as Dictionary
		var achievement_id: String = str(definition.get("id", ""))
		result[achievement_id] = {
			"id": achievement_id,
			"definition_version": int(definition.get("version", DEFINITIONS_VERSION)),
			"attempts": 0,
			"progress": 0,
			"unlocked": false,
			"unlock_count": 0,
		}
	return result


func _event_fingerprint(event: Dictionary) -> String:
	return JSON.stringify(event).sha256_text()


func _event_success(event: Dictionary, newly_unlocked: Array, idempotent: bool) -> Dictionary:
	var unlocked_copy: Array = newly_unlocked.duplicate(true)
	return {
		"success": true,
		"error": "",
		"error_code": "",
		"message": "",
		"changed": not idempotent,
		"idempotent": idempotent,
		"event_type": str(event.get("type", "")),
		"event_id": str(event.get("event_id", "")),
		"attempts": _attempts,
		"newly_unlocked": unlocked_copy,
		"unlocked_ids": unlocked_copy.duplicate(true),
		"state": get_state(),
	}


func _failure(error_code: String, message: String) -> Dictionary:
	return {
		"success": false,
		"error": error_code,
		"error_code": error_code,
		"message": message,
		"changed": false,
	}


func _failure_from(value: Dictionary) -> Dictionary:
	return _failure(str(value.get("error_code", "ACHIEVEMENT_ERROR")), str(value.get("message", "Achievement operation failed.")))


static func _static_failure(error_code: String, message: String) -> Dictionary:
	return {"success": false, "error": error_code, "error_code": error_code, "message": message}


func _add_metric(metrics: Dictionary, metric: String, amount: int) -> void:
	metrics[metric] = maxi(0, int(metrics.get(metric, 0)) + maxi(0, amount))


func _raise_metric(metrics: Dictionary, metric: String, value: int) -> void:
	metrics[metric] = maxi(int(metrics.get(metric, 0)), maxi(0, value))


func _touch_metric(touched: Array, metric: String) -> void:
	if not touched.has(metric):
		touched.append(metric)


static func _canonical_metric_name(value: Variant) -> String:
	var text_value: String = _text_value(value).strip_edges().to_lower()
	if _KNOWN_METRICS.has(text_value):
		return text_value
	return str(_METRIC_ALIASES.get(text_value, ""))


static func _is_known_metric(value: Variant) -> bool:
	return _KNOWN_METRICS.has(_canonical_metric_name(value))


static func _text_value(value: Variant) -> String:
	if typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME:
		return str(value)
	return ""


static func _is_integer_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number: float = value
	return is_finite(number) and floor(number) == number


func _sorted_processed_event_ids() -> Array:
	var values: Array = _processed_event_ids.keys()
	values.sort()
	return values


func _sorted_compendium_puzzle_ids() -> Array:
	var values: Array = _compendium_puzzle_ids.keys()
	values.sort()
	return values


func _sorted_event_fingerprints() -> Dictionary:
	var keys: Array = _processed_event_fingerprints.keys()
	keys.sort()
	var result: Dictionary = {}
	for key: Variant in keys:
		result[str(key)] = str(_processed_event_fingerprints.get(key, ""))
	return result
