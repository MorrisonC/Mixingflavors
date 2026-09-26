extends RefCounted
class_name RunHistoryService

## Pure, deterministic run-history and replay domain service.
##
## The service owns an in-memory, bounded list of run summaries.  It has no
## scene, clock, file, network, random-number, or autoload dependency.  A
## persistence layer may serialize export_snapshot() and pass the resulting
## JSON-compatible value back to load_snapshot().
##
## Core record contract:
##   run_id: non-empty caller ID, or a deterministic ID derived from replay
##           identity when omitted
##   seed: non-negative integer
##   difficulty: easy | medium | hard | endless
##   ruleset_version/catalog_version: non-negative integers
##   depth/score/streak/mistakes: non-negative integers
##   completed: boolean
##   puzzle_ids: ordered array of non-empty strings
##   sequence_fingerprint: SHA-256 of JSON.stringify(puzzle_ids), derived when
##                          omitted and checked when supplied
##   is_daily: optional boolean (defaults to false)
##
## Optional timestamps are copied only when the caller explicitly supplies
## them.  The service never creates a timestamp, UUID, or random value.
## Repeating an identical run_id is idempotent.  Reusing that ID for a
## different canonical record is rejected as RUN_ID_CONFLICT.
##
## History eviction is deterministic: records are retained in insertion order
## and the oldest entries are removed first when the configured bound is
## exceeded.  Re-recording an existing ID does not refresh its position.

const RECORD_SCHEMA_VERSION: int = 1
const SNAPSHOT_SCHEMA_VERSION: int = 1
const CURRENT_SCHEMA_VERSION: int = RECORD_SCHEMA_VERSION
const SCHEMA_VERSION: int = RECORD_SCHEMA_VERSION

const DEFAULT_MAX_HISTORY: int = 20
const MAX_HISTORY_LIMIT: int = 1000
const MAX_RUN_ID_LENGTH: int = 128
const MAX_PUZZLE_ID_LENGTH: int = 256
const MAX_PUZZLE_COUNT: int = 10000
const MAX_TIMESTAMP_LENGTH: int = 128

## Versions this build can actually replay. PuzzleManager owns the catalog and
## the ruleset the daily identity is derived from, so a share token minted
## against a different pair is rejected instead of being replayed under rules
## it was never scored with.
const SUPPORTED_RULESET_VERSION: int = preload("res://scripts/PuzzleManager.gd").RULESET_VERSION
const SUPPORTED_CATALOG_VERSION: int = preload("res://scripts/PuzzleManager.gd").CATALOG_VERSION

const SHARE_TOKEN_PREFIX: String = "mfh1"
const SHARE_TOKEN_SEPARATOR: String = "."
const SHARE_TOKEN_CHECKSUM_LENGTH: int = 12
const SHARE_TOKEN_DOMAIN: String = "mixing-flavors-run-share|1"

const DIFFICULTIES: Array = ["easy", "medium", "hard", "endless"]
const _SHARE_DIFFICULTY_CODES: Dictionary = {
	"easy": "e",
	"medium": "m",
	"hard": "h",
	"endless": "x",
}
const _SHARE_CODE_DIFFICULTIES: Dictionary = {
	"e": "easy",
	"m": "medium",
	"h": "hard",
	"x": "endless",
}

var _max_history: int = DEFAULT_MAX_HISTORY
var _records: Array = []
var _best_score: int = 0
var _best_depth: int = 0
var _best_streak: int = 0
var _best_score_run_id: String = ""
var _best_depth_run_id: String = ""
var _best_streak_run_id: String = ""

# Public convenience property.  Assignment is bounded for convenience; the
# explicit set_max_history() API reports malformed values instead.
var max_history: int:
	get:
		return _max_history
	set(value):
		_max_history = _coerce_max_history(value)
		_evict_to_bound(_records, _max_history)


func _init(requested_max_history: int = DEFAULT_MAX_HISTORY) -> void:
	_max_history = _coerce_max_history(requested_max_history)


# --- Configuration ---------------------------------------------------------

func set_max_history(value: Variant) -> Dictionary:
	var validation: Dictionary = _validate_max_history(value)
	if not bool(validation.get("ok", false)):
		return _failure_from(validation)
	_max_history = int(validation.get("value", DEFAULT_MAX_HISTORY))
	var evicted: Array = _evict_to_bound(_records, _max_history)
	return _success({
		"max_history": _max_history,
		"count": _records.size(),
		"evicted_run_ids": evicted,
	})


func configure(value: Variant) -> Dictionary:
	return set_max_history(value)


func get_max_history() -> int:
	return _max_history


func get_history_limit() -> int:
	return _max_history


# --- Record validation and mutation ---------------------------------------

## Normalizes a caller record without changing it.  A successful result has
## `record`; a failed result has stable `error_code` and `message` fields.
func normalize_record(value: Variant) -> Dictionary:
	var normalized: Dictionary = _normalize_record_internal(value)
	if not bool(normalized.get("ok", false)):
		return _failure_from(normalized)
	var record: Dictionary = normalized.get("record", {}) as Dictionary
	return _success({
		"record": record.duplicate(true),
		"run_id": str(record.get("run_id", "")),
		"run_id_generated": bool(normalized.get("run_id_generated", false)),
	})


func is_valid_record(value: Variant) -> bool:
	return bool(_normalize_record_internal(value).get("ok", false))


func validate_record(value: Variant) -> Dictionary:
	return normalize_record(value)


func derive_run_id(value: Variant) -> Dictionary:
	var normalized: Dictionary = normalize_record(value)
	if not bool(normalized.get("success", false)):
		return normalized
	var record: Dictionary = normalized.get("record", {}) as Dictionary
	return _success({
		"run_id": str(record.get("run_id", "")),
		"generated": bool(normalized.get("run_id_generated", false)),
	})


## Records a run.  The only committed state is reached after the complete
## record has validated and, for a duplicate ID, after conflict checking.
func record_run(value: Variant) -> Dictionary:
	var normalized: Dictionary = _normalize_record_internal(value)
	if not bool(normalized.get("ok", false)):
		return _failure_from(normalized)

	var record: Dictionary = normalized.get("record", {}) as Dictionary
	var run_id: String = str(record.get("run_id", ""))
	for existing_value: Variant in _records:
		var existing: Dictionary = existing_value as Dictionary
		if str(existing.get("run_id", "")) != run_id:
			continue
		if existing == record:
			return _record_result(record, false, false, true, [])
		return _failure(
			"RUN_ID_CONFLICT",
			"run_id '%s' is already associated with a different run summary." % run_id
		)

	var working: Array = _records.duplicate(true)
	working.append(record.duplicate(true))
	var evicted: Array = _evict_to_bound(working, _max_history)
	_records = working
	_update_best_from_record(record)
	return _record_result(record, true, true, false, evicted)


func record(value: Variant) -> Dictionary:
	return record_run(value)


func record_result(value: Variant) -> Dictionary:
	return record_run(value)


func upsert_run(value: Variant) -> Dictionary:
	return record_run(value)


func get_run(run_id: Variant) -> Dictionary:
	var result: Dictionary = find_run(run_id)
	return (result.get("record", {}) as Dictionary).duplicate(true) if bool(result.get("found", false)) else {}


func find_run(run_id: Variant) -> Dictionary:
	if typeof(run_id) != TYPE_STRING:
		return _failure("INVALID_RUN_ID", "run_id must be a non-empty string.")
	var normalized_id: String = str(run_id).strip_edges()
	if normalized_id.is_empty() or normalized_id.length() > MAX_RUN_ID_LENGTH:
		return _failure("INVALID_RUN_ID", "run_id must be between 1 and %d characters." % MAX_RUN_ID_LENGTH)
	for existing_value: Variant in _records:
		var existing: Dictionary = existing_value as Dictionary
		if str(existing.get("run_id", "")) == normalized_id:
			return _success({
				"found": true,
				"record": existing.duplicate(true),
			})
	return _success({"found": false, "record": {}})


func has_run(run_id: Variant) -> bool:
	return bool(find_run(run_id).get("found", false))


# --- History reads and filtering -------------------------------------------

func get_all_runs() -> Array:
	return _records.duplicate(true)


func get_history() -> Array:
	return get_all_runs()


## Returns records matching all supplied filters.  Invalid filters produce an
## empty result here; query_runs() exposes the diagnostic envelope.
func filter_runs(filters: Variant = {}) -> Array:
	var result: Dictionary = query_runs(filters)
	return (result.get("runs", []) as Array).duplicate(true) if bool(result.get("success", false)) else []


func get_filtered_runs(filters: Variant = {}) -> Array:
	return filter_runs(filters)


## Positional convenience form: get_runs("hard", true, 1234).
func get_runs(
	difficulty: Variant = null,
	daily: Variant = null,
	seed: Variant = null
) -> Array:
	var filters: Dictionary = {}
	if difficulty != null:
		filters["difficulty"] = difficulty
	if daily != null:
		filters["daily"] = daily
	if seed != null:
		filters["seed"] = seed
	return filter_runs(filters)


func query_runs(filters: Variant = {}) -> Dictionary:
	var normalized: Dictionary = _normalize_filters(filters)
	if not bool(normalized.get("ok", false)):
		return _failure_from(normalized)

	var has_difficulty: bool = bool(normalized.get("has_difficulty", false))
	var has_daily: bool = bool(normalized.get("has_daily", false))
	var has_seed: bool = bool(normalized.get("has_seed", false))
	var difficulty: String = str(normalized.get("difficulty", ""))
	var daily: bool = bool(normalized.get("daily", false))
	var seed: int = int(normalized.get("seed", 0))
	var runs: Array = []
	for record_value: Variant in _records:
		var record: Dictionary = record_value as Dictionary
		if has_difficulty and str(record.get("difficulty", "")) != difficulty:
			continue
		if has_daily and bool(record.get("is_daily", false)) != daily:
			continue
		if has_seed and int(record.get("seed", -1)) != seed:
			continue
		runs.append(record.duplicate(true))
	return _success({"runs": runs, "count": runs.size()})


func get_daily_runs() -> Array:
	return filter_runs({"daily": true})


func get_runs_by_seed(seed: Variant) -> Array:
	return filter_runs({"seed": seed})


func get_runs_by_difficulty(difficulty: Variant) -> Array:
	return filter_runs({"difficulty": difficulty})


# --- Aggregates ------------------------------------------------------------

## Aggregates expose best values across the service lifetime, while total_runs
## and completed_runs describe the currently retained bounded history.  Best
## values therefore do not disappear merely because an old record is evicted;
## the values are carried in the snapshot for reload.
func get_aggregates() -> Dictionary:
	var completed_runs: int = 0
	var retained_best_score: int = 0
	var retained_best_depth: int = 0
	var retained_best_streak: int = 0
	var retained_best_score_run_id: String = ""
	var retained_best_depth_run_id: String = ""
	var retained_best_streak_run_id: String = ""

	for record_value: Variant in _records:
		var record: Dictionary = record_value as Dictionary
		if bool(record.get("completed", false)):
			completed_runs += 1
		var score: int = int(record.get("score", 0))
		var depth: int = int(record.get("depth", 0))
		var streak: int = int(record.get("streak", 0))
		var run_id: String = str(record.get("run_id", ""))
		if score > retained_best_score:
			retained_best_score = score
			retained_best_score_run_id = run_id
		if depth > retained_best_depth:
			retained_best_depth = depth
			retained_best_depth_run_id = run_id
		if streak > retained_best_streak:
			retained_best_streak = streak
			retained_best_streak_run_id = run_id

	var best_score: int = maxi(_best_score, retained_best_score)
	var best_depth: int = maxi(_best_depth, retained_best_depth)
	var best_streak: int = maxi(_best_streak, retained_best_streak)
	var best_score_run_id: String = _best_score_run_id if _best_score >= retained_best_score else retained_best_score_run_id
	var best_depth_run_id: String = _best_depth_run_id if _best_depth >= retained_best_depth else retained_best_depth_run_id
	var best_streak_run_id: String = _best_streak_run_id if _best_streak >= retained_best_streak else retained_best_streak_run_id

	return {
		"total_runs": _records.size(),
		"run_count": _records.size(),
		"completed_runs": completed_runs,
		"completion_count": completed_runs,
		"best_score": best_score,
		"best_depth": best_depth,
		"best_streak": best_streak,
		"best_score_run_id": best_score_run_id,
		"best_depth_run_id": best_depth_run_id,
		"best_streak_run_id": best_streak_run_id,
		"best": {
			"score": best_score,
			"depth": best_depth,
			"streak": best_streak,
		},
	}


func get_best_stats() -> Dictionary:
	return get_aggregates()


func get_aggregate_stats() -> Dictionary:
	return get_aggregates()


func get_best_aggregates() -> Dictionary:
	return get_aggregates()


# --- JSON-compatible snapshots --------------------------------------------

func export_snapshot() -> Dictionary:
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"version": SNAPSHOT_SCHEMA_VERSION,
		"max_history": _max_history,
		"records": get_all_runs(),
		"aggregates": get_aggregates(),
	}


func get_snapshot() -> Dictionary:
	return export_snapshot()


func export_history() -> Dictionary:
	return export_snapshot()


func get_history_snapshot() -> Dictionary:
	return export_snapshot()


func export_json() -> String:
	return JSON.stringify(export_snapshot())


func export_json_string() -> String:
	return export_json()


## Replaces the local state only after every record and the snapshot shape has
## validated.  A snapshot may be a Dictionary or the text returned by JSON
## serialization.  Older record inputs may omit schema_version; it is stamped
## with the current version during normalization.
func load_snapshot(snapshot: Variant) -> Dictionary:
	var source: Dictionary = {}
	if typeof(snapshot) == TYPE_STRING:
		var parsed: Variant = JSON.parse_string(str(snapshot))
		if typeof(parsed) == TYPE_DICTIONARY:
			source = parsed as Dictionary
		elif typeof(parsed) == TYPE_ARRAY:
			source = {
				"schema_version": SNAPSHOT_SCHEMA_VERSION,
				"records": (parsed as Array).duplicate(true),
			}
		else:
			return _failure("INVALID_SNAPSHOT", "Snapshot text must contain a JSON object or array.")
	elif typeof(snapshot) == TYPE_DICTIONARY:
		source = (snapshot as Dictionary).duplicate(true)
	elif typeof(snapshot) == TYPE_ARRAY:
		# A raw history array is a convenient persistence shape; it is
		# normalized into the same versioned wrapper before validation.
		source = {
			"schema_version": SNAPSHOT_SCHEMA_VERSION,
			"records": (snapshot as Array).duplicate(true),
		}
	else:
		return _failure("INVALID_SNAPSHOT", "Snapshot must be a dictionary, an array, or JSON object text.")

	var schema_validation: Dictionary = _read_optional_schema(source)
	if not bool(schema_validation.get("ok", false)):
		return _failure_from(schema_validation)
	if bool(schema_validation.get("present", false)) and int(schema_validation.get("value", -1)) != SNAPSHOT_SCHEMA_VERSION:
		return _failure("UNSUPPORTED_SNAPSHOT_SCHEMA", "Unsupported run-history snapshot schema version.")

	var working_max: int = _max_history
	if source.has("max_history"):
		var max_validation: Dictionary = _validate_max_history(source.get("max_history", null))
		if not bool(max_validation.get("ok", false)):
			return _failure("INVALID_SNAPSHOT_MAX_HISTORY", max_validation.get("message", "max_history is invalid."))
		working_max = int(max_validation.get("value", DEFAULT_MAX_HISTORY))

	var records_value: Variant = null
	var records_key: String = ""
	for candidate: String in ["records", "history", "runs"]:
		if source.has(candidate):
			records_key = candidate
			records_value = source.get(candidate, null)
			break
	if records_key.is_empty():
		return _failure("INVALID_SNAPSHOT", "Snapshot must contain a records array.")

	var working_records: Array = []
	var seen_ids: Dictionary = {}
	if typeof(records_value) == TYPE_ARRAY:
		var raw_records: Array = records_value as Array
		for raw_record: Variant in raw_records:
			var normalized: Dictionary = _normalize_record_internal(raw_record)
			if not bool(normalized.get("ok", false)):
				return _failure("INVALID_RUN_RECORD", str(normalized.get("message", "Malformed run record.")))
			var record: Dictionary = normalized.get("record", {}) as Dictionary
			var run_id: String = str(record.get("run_id", ""))
			if seen_ids.has(run_id):
				return _failure("DUPLICATE_RUN_ID", "Snapshot contains more than one record for run_id '%s'." % run_id)
			seen_ids[run_id] = true
			working_records.append(record)
	elif typeof(records_value) == TYPE_DICTIONARY:
		var raw_map: Dictionary = records_value as Dictionary
		for raw_key: Variant in raw_map.keys():
			var raw_record_value: Variant = raw_map.get(raw_key, null)
			var candidate_record: Dictionary = raw_record_value as Dictionary if typeof(raw_record_value) == TYPE_DICTIONARY else {}
			if candidate_record.is_empty() and not (candidate_record.has("run_id") or candidate_record.has("id")):
				candidate_record = {"run_id": str(raw_key)}
			var normalized: Dictionary = _normalize_record_internal(candidate_record)
			if not bool(normalized.get("ok", false)):
				return _failure("INVALID_RUN_RECORD", str(normalized.get("message", "Malformed run record.")))
			var record: Dictionary = normalized.get("record", {}) as Dictionary
			var run_id: String = str(record.get("run_id", ""))
			if seen_ids.has(run_id):
				return _failure("DUPLICATE_RUN_ID", "Snapshot contains more than one record for run_id '%s'." % run_id)
			seen_ids[run_id] = true
			working_records.append(record)
	else:
		return _failure("INVALID_SNAPSHOT", "Snapshot records must be an array or run_id map.")

	var best_validation: Dictionary = _normalize_snapshot_best(source, working_records)
	if not bool(best_validation.get("ok", false)):
		return _failure_from(best_validation)
	var evicted: Array = _evict_to_bound(working_records, working_max)
	_commit_best(best_validation.get("best", {}) as Dictionary)
	_records = working_records
	_max_history = working_max
	return _success({
		"count": _records.size(),
		"max_history": _max_history,
		"evicted_run_ids": evicted,
		"aggregates": get_aggregates(),
	})


func load_state(snapshot: Variant) -> Dictionary:
	return load_snapshot(snapshot)


func load_history(snapshot: Variant) -> Dictionary:
	return load_snapshot(snapshot)


func load_history_snapshot(snapshot: Variant) -> Dictionary:
	return load_snapshot(snapshot)


func load_local_history(snapshot: Variant) -> Dictionary:
	return load_snapshot(snapshot)


func reload_snapshot(snapshot: Variant) -> Dictionary:
	return load_snapshot(snapshot)


func load_json(text: Variant) -> Dictionary:
	return load_snapshot(text)


func clear() -> Dictionary:
	_records.clear()
	_reset_best()
	return _success({"count": 0})


func clear_history() -> Dictionary:
	return clear()


# --- Share tokens ----------------------------------------------------------

## Builds a compact, URL-safe token containing only replay identity:
## seed, normalized difficulty, ruleset version, and catalog version.  The
## short checksum is a public integrity check, not a secret or authentication
## mechanism.  No score, puzzle sequence, run ID, or timestamp is included.
##
## The first argument may be a seed, or a complete run record Dictionary.  The
## explicit four-argument form is useful when a caller has not built a record.
func encode_share_token(
	seed_or_record: Variant,
	difficulty: Variant = null,
	ruleset_version: Variant = null,
	catalog_version: Variant = null
) -> Dictionary:
	var seed_value: Variant = seed_or_record
	var difficulty_value: Variant = difficulty
	var ruleset_value: Variant = ruleset_version
	var catalog_value: Variant = catalog_version

	if typeof(seed_or_record) == TYPE_DICTIONARY:
		if difficulty != null or ruleset_version != null or catalog_version != null:
			return _failure("INVALID_SHARE_ARGUMENTS", "A record share token cannot also receive identity arguments.")
		var normalized_record: Dictionary = normalize_record(seed_or_record)
		if not bool(normalized_record.get("success", false)):
			return _failure("INVALID_SHARE_RECORD", str(normalized_record.get("message", "Run record is invalid.")))
		var source_record: Dictionary = normalized_record.get("record", {}) as Dictionary
		seed_value = source_record.get("seed", null)
		difficulty_value = source_record.get("difficulty", null)
		ruleset_value = source_record.get("ruleset_version", null)
		catalog_value = source_record.get("catalog_version", null)

	var identity: Dictionary = _normalize_share_identity(seed_value, difficulty_value, ruleset_value, catalog_value)
	if not bool(identity.get("ok", false)):
		return _failure_from(identity)

	var normalized_identity: Dictionary = identity.get("identity", {}) as Dictionary
	var token: String = _build_share_token(normalized_identity)
	return _success({
		"token": token,
		"share_token": token,
		"seed": int(normalized_identity.get("seed", 0)),
		"difficulty": str(normalized_identity.get("difficulty", "")),
		"ruleset_version": int(normalized_identity.get("ruleset_version", 0)),
		"catalog_version": int(normalized_identity.get("catalog_version", 0)),
	})


func encode_share_for_record(record: Variant) -> Dictionary:
	return encode_share_token(record)


func encode_share(
	seed_or_record: Variant,
	difficulty: Variant = null,
	ruleset_version: Variant = null,
	catalog_version: Variant = null
) -> Dictionary:
	return encode_share_token(seed_or_record, difficulty, ruleset_version, catalog_version)


func make_share_token(
	seed_or_record: Variant,
	difficulty: Variant = null,
	ruleset_version: Variant = null,
	catalog_version: Variant = null
) -> String:
	var result: Dictionary = encode_share_token(seed_or_record, difficulty, ruleset_version, catalog_version)
	return str(result.get("token", "")) if bool(result.get("success", false)) else ""


func build_share_token(
	seed_or_record: Variant,
	difficulty: Variant = null,
	ruleset_version: Variant = null,
	catalog_version: Variant = null
) -> String:
	return make_share_token(seed_or_record, difficulty, ruleset_version, catalog_version)


func decode_share_token(token: Variant) -> Dictionary:
	if typeof(token) == TYPE_DICTIONARY:
		var token_envelope: Dictionary = token as Dictionary
		if not bool(token_envelope.get("success", false)) or typeof(token_envelope.get("token", null)) != TYPE_STRING:
			return _failure("INVALID_SHARE_TOKEN", "Share token envelope is invalid.")
		token = token_envelope.get("token", "")
	if typeof(token) != TYPE_STRING:
		return _failure("INVALID_SHARE_TOKEN", "Share token must be a string.")
	var token_text: String = str(token)
	if token_text.is_empty() or token_text != token_text.strip_edges():
		return _failure("INVALID_SHARE_TOKEN", "Share token is empty or contains surrounding whitespace.")
	var parts: PackedStringArray = token_text.split(SHARE_TOKEN_SEPARATOR, true)
	if parts.size() != 6 or str(parts[0]) != SHARE_TOKEN_PREFIX:
		return _failure("INVALID_SHARE_TOKEN", "Share token has an invalid shape.")

	var seed_parse: Dictionary = _parse_decimal_nonnegative(str(parts[1]))
	var ruleset_parse: Dictionary = _parse_decimal_nonnegative(str(parts[3]))
	var catalog_parse: Dictionary = _parse_decimal_nonnegative(str(parts[4]))
	if not bool(seed_parse.get("ok", false)) or not bool(ruleset_parse.get("ok", false)) or not bool(catalog_parse.get("ok", false)):
		return _failure("INVALID_SHARE_TOKEN", "Share token contains an invalid non-negative integer.")

	var difficulty: String = str(_SHARE_CODE_DIFFICULTIES.get(str(parts[2]), ""))
	if difficulty.is_empty():
		return _failure("INVALID_SHARE_TOKEN", "Share token contains an unsupported difficulty.")

	var seed_value: int = int(seed_parse.get("value", 0))
	var ruleset_value: int = int(ruleset_parse.get("value", 0))
	var catalog_value: int = int(catalog_parse.get("value", 0))
	var expected_checksum: String = _share_checksum(seed_value, difficulty, ruleset_value, catalog_value)
	if str(parts[5]) != expected_checksum:
		return _failure("SHARE_TOKEN_TAMPERED", "Share token checksum does not match its replay identity.")
	# A structurally valid token can still name an identity this build does not
	# implement. Reject it explicitly instead of replaying it under current
	# rules, which would apply this build's scoring to a foreign identity.
	var expected_ruleset: int = SUPPORTED_RULESET_VERSION
	var expected_catalog: int = SUPPORTED_CATALOG_VERSION
	if ruleset_value != expected_ruleset or catalog_value != expected_catalog:
		return _failure("SHARE_TOKEN_VERSION_MISMATCH", "Share token was minted for ruleset %d/catalog %d; this build supports %d/%d." % [ruleset_value, catalog_value, expected_ruleset, expected_catalog])

	var identity: Dictionary = {
		"seed": seed_value,
		"difficulty": difficulty,
		"ruleset_version": ruleset_value,
		"catalog_version": catalog_value,
	}
	return _success({
		"token": token_text,
		"seed": seed_value,
		"difficulty": difficulty,
		"ruleset_version": ruleset_value,
		"catalog_version": catalog_value,
		"replay": identity.duplicate(true),
	})


func parse_share_token(token: Variant) -> Dictionary:
	return decode_share_token(token)


func decode_share(token: Variant) -> Dictionary:
	return decode_share_token(token)


func decode_replay_token(token: Variant) -> Dictionary:
	return decode_share_token(token)


func share_token_for_run(run_id: Variant) -> Dictionary:
	var found: Dictionary = find_run(run_id)
	if not bool(found.get("found", false)):
		return _failure("RUN_NOT_FOUND", "No local run exists for the supplied run_id.")
	return encode_share_token(found.get("record", {}) as Dictionary)


# --- Public deterministic helpers -----------------------------------------

static func is_valid_sequence_fingerprint(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var fingerprint: String = str(value).strip_edges().to_lower()
	if fingerprint.length() != 64:
		return false
	for index: int in range(fingerprint.length()):
		if not _is_hex_digit(fingerprint.unicode_at(index)):
			return false
	return true


static func fingerprint_sequence(puzzle_ids: Variant) -> String:
	if typeof(puzzle_ids) != TYPE_ARRAY:
		return ""
	var ids: Array = puzzle_ids as Array
	if ids.size() > MAX_PUZZLE_COUNT:
		return ""
	var canonical_ids: Array = []
	for puzzle_id: Variant in ids:
		if typeof(puzzle_id) != TYPE_STRING:
			return ""
		var id_text: String = str(puzzle_id).strip_edges()
		if id_text.is_empty() or id_text.length() > MAX_PUZZLE_ID_LENGTH:
			return ""
		canonical_ids.append(id_text)
	return JSON.stringify(canonical_ids).sha256_text()


static func sequence_fingerprint(puzzle_ids: Variant) -> String:
	return fingerprint_sequence(puzzle_ids)


# --- Internal record normalization ----------------------------------------

func _normalize_record_internal(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure_internal("INVALID_RUN_RECORD", "Run record must be a dictionary.")
	var source: Dictionary = value as Dictionary

	var schema_validation: Dictionary = _read_optional_schema(source)
	if not bool(schema_validation.get("ok", false)):
		return schema_validation
	if bool(schema_validation.get("present", false)) and int(schema_validation.get("value", -1)) != RECORD_SCHEMA_VERSION:
		return _failure_internal("UNSUPPORTED_RUN_RECORD_SCHEMA", "Unsupported run record schema version.")

	var seed_validation: Dictionary = _read_required_nonnegative(source, ["seed", "run_seed"], "seed", "INVALID_SEED")
	if not bool(seed_validation.get("ok", false)):
		return seed_validation
	var difficulty_validation: Dictionary = _read_required_string(source, ["difficulty", "mode"], "difficulty", "INVALID_DIFFICULTY")
	if not bool(difficulty_validation.get("ok", false)):
		return difficulty_validation
	var difficulty_value: String = str(difficulty_validation.get("value", "")).strip_edges().to_lower()
	if not (difficulty_value in DIFFICULTIES):
		return _failure_internal("INVALID_DIFFICULTY", "difficulty must be easy, medium, hard, or endless.")

	var ruleset_validation: Dictionary = _read_required_nonnegative(source, ["ruleset_version", "ruleset"], "ruleset_version", "INVALID_RULESET_VERSION")
	if not bool(ruleset_validation.get("ok", false)):
		return ruleset_validation
	var catalog_validation: Dictionary = _read_required_nonnegative(source, ["catalog_version", "catalog"], "catalog_version", "INVALID_CATALOG_VERSION")
	if not bool(catalog_validation.get("ok", false)):
		return catalog_validation

	var depth_validation: Dictionary = _read_required_nonnegative(source, ["depth"], "depth", "INVALID_DEPTH")
	if not bool(depth_validation.get("ok", false)):
		return depth_validation
	var score_validation: Dictionary = _read_required_nonnegative(source, ["score"], "score", "INVALID_SCORE")
	if not bool(score_validation.get("ok", false)):
		return score_validation
	var streak_validation: Dictionary = _read_required_nonnegative(source, ["streak", "best_streak"], "streak", "INVALID_STREAK")
	if not bool(streak_validation.get("ok", false)):
		return streak_validation
	var mistakes_validation: Dictionary = _read_required_nonnegative(source, ["mistakes"], "mistakes", "INVALID_MISTAKES")
	if not bool(mistakes_validation.get("ok", false)):
		return mistakes_validation

	var completed_validation: Dictionary = _read_required_alias(source, ["completed", "is_completed", "completion"], "completed", "INVALID_COMPLETION")
	if not bool(completed_validation.get("ok", false)):
		return completed_validation
	if typeof(completed_validation.get("value", null)) != TYPE_BOOL:
		return _failure_internal("INVALID_COMPLETION", "completed must be a boolean.")

	var puzzle_validation: Dictionary = _read_required_alias(source, ["puzzle_ids", "sequence"], "puzzle_ids", "INVALID_PUZZLE_IDS")
	if not bool(puzzle_validation.get("ok", false)):
		return puzzle_validation
	if typeof(puzzle_validation.get("value", null)) != TYPE_ARRAY:
		return _failure_internal("INVALID_PUZZLE_IDS", "puzzle_ids must be an array of strings.")
	var raw_puzzle_ids: Array = puzzle_validation.get("value", []) as Array
	if raw_puzzle_ids.size() > MAX_PUZZLE_COUNT:
		return _failure_internal("INVALID_PUZZLE_IDS", "puzzle_ids exceeds the supported sequence length.")
	var puzzle_ids: Array = []
	for puzzle_id: Variant in raw_puzzle_ids:
		if typeof(puzzle_id) != TYPE_STRING:
			return _failure_internal("INVALID_PUZZLE_IDS", "puzzle_ids must contain only strings.")
		var id_text: String = str(puzzle_id).strip_edges()
		if id_text.is_empty() or id_text.length() > MAX_PUZZLE_ID_LENGTH:
			return _failure_internal("INVALID_PUZZLE_IDS", "puzzle_ids must contain non-empty bounded strings.")
		puzzle_ids.append(id_text)

	var calculated_fingerprint: String = fingerprint_sequence(puzzle_ids)
	if calculated_fingerprint.is_empty():
		return _failure_internal("INVALID_PUZZLE_IDS", "puzzle_ids could not be fingerprinted.")
	var fingerprint_validation: Dictionary = _read_optional_alias(source, ["sequence_fingerprint", "sequence_hash", "fingerprint"], "INVALID_SEQUENCE_FINGERPRINT")
	if not bool(fingerprint_validation.get("ok", false)):
		return fingerprint_validation
	var supplied_fingerprint: String = ""
	if bool(fingerprint_validation.get("present", false)):
		if not is_valid_sequence_fingerprint(fingerprint_validation.get("value", null)):
			return _failure_internal("INVALID_SEQUENCE_FINGERPRINT", "sequence_fingerprint must be a 64-character hexadecimal SHA-256 value.")
		supplied_fingerprint = str(fingerprint_validation.get("value", "")).strip_edges().to_lower()
		if supplied_fingerprint != calculated_fingerprint:
			return _failure_internal("SEQUENCE_FINGERPRINT_MISMATCH", "sequence_fingerprint does not match puzzle_ids.")

	var run_id_validation: Dictionary = _read_optional_alias(source, ["run_id", "id"], "INVALID_RUN_ID")
	if not bool(run_id_validation.get("ok", false)):
		return run_id_validation
	var run_id: String = ""
	var run_id_generated: bool = false
	if bool(run_id_validation.get("present", false)):
		if typeof(run_id_validation.get("value", null)) != TYPE_STRING:
			return _failure_internal("INVALID_RUN_ID", "run_id must be a non-empty string.")
		run_id = str(run_id_validation.get("value", "")).strip_edges()
		if run_id.is_empty() or run_id.length() > MAX_RUN_ID_LENGTH or _has_control_character(run_id):
			return _failure_internal("INVALID_RUN_ID", "run_id must be a non-empty bounded printable string.")

	var daily_validation: Dictionary = _read_optional_alias(source, ["is_daily", "daily", "daily_challenge"], "INVALID_DAILY_FLAG")
	if not bool(daily_validation.get("ok", false)):
		return daily_validation
	var daily_id_present: bool = source.has("daily_id")
	var daily_date_present: bool = source.has("daily_date") or source.has("date")
	var is_daily: bool = daily_id_present or daily_date_present
	if bool(daily_validation.get("present", false)):
		if typeof(daily_validation.get("value", null)) != TYPE_BOOL:
			return _failure_internal("INVALID_DAILY_FLAG", "is_daily must be a boolean.")
		is_daily = bool(daily_validation.get("value", false))
		if not is_daily and (daily_id_present or daily_date_present):
			return _failure_internal("DAILY_IDENTITY_MISMATCH", "Daily identity fields cannot accompany is_daily=false.")

	var daily_id: Variant = null
	var daily_id_present_in_output: bool = false
	if daily_id_present:
		daily_id = source.get("daily_id", null)
		# Use the shared integer validator rather than a raw TYPE_INT check: a
		# JSON round trip materializes every number as a float, so a stored
		# daily_id comes back as 777777.0. A strict int-only check rejected the
		# whole snapshot, which meant the first daily run a player completed
		# permanently poisoned their run history on the next launch.
		if _is_integer_value(daily_id):
			if int(daily_id) < 0:
				return _failure_internal("INVALID_DAILY_ID", "daily_id cannot be negative.")
			daily_id = int(daily_id)
			daily_id_present_in_output = true
		elif typeof(daily_id) == TYPE_STRING:
			var daily_id_text: String = str(daily_id).strip_edges()
			if daily_id_text.is_empty() or daily_id_text.length() > MAX_RUN_ID_LENGTH or _has_control_character(daily_id_text):
				return _failure_internal("INVALID_DAILY_ID", "daily_id must be a non-empty bounded string when textual.")
			daily_id = daily_id_text
			daily_id_present_in_output = true
		else:
			return _failure_internal("INVALID_DAILY_ID", "daily_id must be a non-negative integer or non-empty string.")
	var daily_date: String = ""
	var daily_date_present_in_output: bool = false
	if daily_date_present:
		if source.has("daily_date") and source.has("date") and source.get("daily_date", null) != source.get("date", null):
			return _failure_internal("INVALID_DAILY_DATE", "daily_date aliases do not match.")
		var date_value: Variant = source.get("daily_date", source.get("date", null))
		if typeof(date_value) != TYPE_STRING or not _is_canonical_date_shape(str(date_value)):
			return _failure_internal("INVALID_DAILY_DATE", "daily_date must use canonical YYYY-MM-DD format.")
		daily_date = str(date_value)
		daily_date_present_in_output = true

	if is_daily == false and (daily_id_present_in_output or daily_date_present_in_output):
		return _failure_internal("DAILY_IDENTITY_MISMATCH", "Daily identity fields require is_daily=true.")

	var timestamp_validation: Dictionary = _normalize_timestamps(source)
	if not bool(timestamp_validation.get("ok", false)):
		return timestamp_validation
	var timestamps: Dictionary = timestamp_validation.get("timestamps", {}) as Dictionary

	var record: Dictionary = {
		"schema_version": RECORD_SCHEMA_VERSION,
		"run_id": run_id,
		"seed": int(seed_validation.get("value", 0)),
		"difficulty": difficulty_value,
		"ruleset_version": int(ruleset_validation.get("value", 0)),
		"catalog_version": int(catalog_validation.get("value", 0)),
		"depth": int(depth_validation.get("value", 0)),
		"score": int(score_validation.get("value", 0)),
		"streak": int(streak_validation.get("value", 0)),
		"mistakes": int(mistakes_validation.get("value", 0)),
		"completed": bool(completed_validation.get("value", false)),
		"puzzle_ids": puzzle_ids.duplicate(true),
		"sequence_fingerprint": calculated_fingerprint,
		"is_daily": is_daily,
		"daily": is_daily,
	}
	if run_id.is_empty():
		run_id = _derive_run_id(record, daily_id_present_in_output, daily_id, daily_date_present_in_output, daily_date)
		run_id_generated = true
		record["run_id"] = run_id
	if daily_id_present_in_output:
		record["daily_id"] = daily_id
	if daily_date_present_in_output:
		record["daily_date"] = daily_date
	for timestamp_key: String in timestamps.keys():
		record[timestamp_key] = timestamps[timestamp_key]

	return {
		"ok": true,
		"record": record,
		"run_id_generated": run_id_generated,
	}


func _record_result(
	record: Dictionary,
	added: bool,
	changed: bool,
	idempotent: bool,
	evicted: Array
) -> Dictionary:
	var result: Dictionary = _success({
		"run_id": str(record.get("run_id", "")),
		"record": record.duplicate(true),
		"result": record.duplicate(true),
		"added": added,
		"updated": changed and not added,
		"changed": changed,
		"idempotent": idempotent,
		"history_size": _records.size(),
		"count": _records.size(),
		"max_history": _max_history,
		"evicted_run_ids": evicted.duplicate(true),
		"aggregates": get_aggregates(),
	})
	return result


# --- Filters, snapshots, and token helpers --------------------------------

func _reset_best() -> void:
	_best_score = 0
	_best_depth = 0
	_best_streak = 0
	_best_score_run_id = ""
	_best_depth_run_id = ""
	_best_streak_run_id = ""


func _update_best_from_record(record: Dictionary) -> void:
	var run_id: String = str(record.get("run_id", ""))
	var score: int = int(record.get("score", 0))
	var depth: int = int(record.get("depth", 0))
	var streak: int = int(record.get("streak", 0))
	if score > _best_score:
		_best_score = score
		_best_score_run_id = run_id
	if depth > _best_depth:
		_best_depth = depth
		_best_depth_run_id = run_id
	if streak > _best_streak:
		_best_streak = streak
		_best_streak_run_id = run_id


func _best_from_records(records: Array) -> Dictionary:
	var best: Dictionary = {
		"best_score": 0,
		"best_depth": 0,
		"best_streak": 0,
		"best_score_run_id": "",
		"best_depth_run_id": "",
		"best_streak_run_id": "",
	}
	for record_value: Variant in records:
		_update_best_dictionary(best, record_value as Dictionary)
	return best


func _update_best_dictionary(best: Dictionary, record: Dictionary) -> void:
	var run_id: String = str(record.get("run_id", ""))
	var score: int = int(record.get("score", 0))
	var depth: int = int(record.get("depth", 0))
	var streak: int = int(record.get("streak", 0))
	if score > int(best.get("best_score", 0)):
		best["best_score"] = score
		best["best_score_run_id"] = run_id
	if depth > int(best.get("best_depth", 0)):
		best["best_depth"] = depth
		best["best_depth_run_id"] = run_id
	if streak > int(best.get("best_streak", 0)):
		best["best_streak"] = streak
		best["best_streak_run_id"] = run_id


func _normalize_snapshot_best(source: Dictionary, records: Array) -> Dictionary:
	var derived: Dictionary = _best_from_records(records)
	if not source.has("aggregates"):
		return {"ok": true, "best": derived}
	var aggregate_value: Variant = source.get("aggregates", null)
	if typeof(aggregate_value) != TYPE_DICTIONARY:
		return _failure_internal("INVALID_SNAPSHOT_AGGREGATES", "Snapshot aggregates must be a dictionary when supplied.")
	var aggregate: Dictionary = aggregate_value as Dictionary
	var result: Dictionary = derived.duplicate(true)
	var metric_ids: Dictionary = {
		"best_score": "best_score_run_id",
		"best_depth": "best_depth_run_id",
		"best_streak": "best_streak_run_id",
	}
	for metric: String in ["best_score", "best_depth", "best_streak"]:
		if not aggregate.has(metric):
			continue
		var value: Variant = aggregate.get(metric, null)
		var validation: Dictionary = _validate_nonnegative_integer(value, metric, "INVALID_SNAPSHOT_AGGREGATES")
		if not bool(validation.get("ok", false)):
			return validation
		var aggregate_value_int: int = int(validation.get("value", 0))
		var derived_value: int = int(result.get(metric, 0))
		result[metric] = maxi(derived_value, aggregate_value_int)
		var id_metric: String = str(metric_ids.get(metric, ""))
		if aggregate_value_int >= derived_value and id_metric.length() > 0:
			var run_id_value: Variant = aggregate.get(id_metric, null)
			if run_id_value != null:
				if typeof(run_id_value) != TYPE_STRING:
					return _failure_internal("INVALID_SNAPSHOT_AGGREGATES", "%s must be a string." % id_metric)
				if not str(run_id_value).is_empty():
					# IDs may refer to records already evicted from the bounded
					# list; retaining the descriptive ID preserves the best.
					result[id_metric] = run_id_value
	return {"ok": true, "best": result}


func _commit_best(best: Dictionary) -> void:
	_best_score = int(best.get("best_score", 0))
	_best_depth = int(best.get("best_depth", 0))
	_best_streak = int(best.get("best_streak", 0))
	_best_score_run_id = str(best.get("best_score_run_id", ""))
	_best_depth_run_id = str(best.get("best_depth_run_id", ""))
	_best_streak_run_id = str(best.get("best_streak_run_id", ""))


func _normalize_filters(value: Variant) -> Dictionary:
	if value == null:
		return {"ok": true, "has_difficulty": false, "has_daily": false, "has_seed": false}
	if typeof(value) != TYPE_DICTIONARY:
		return _failure_internal("INVALID_FILTER", "Run filters must be a dictionary.")
	var source: Dictionary = value as Dictionary
	var result: Dictionary = {
		"ok": true,
		"has_difficulty": false,
		"has_daily": false,
		"has_seed": false,
	}

	var difficulty_result: Dictionary = _read_optional_alias(source, ["difficulty", "mode"], "INVALID_FILTER_DIFFICULTY")
	if not bool(difficulty_result.get("ok", false)):
		return difficulty_result
	if bool(difficulty_result.get("present", false)):
		if typeof(difficulty_result.get("value", null)) != TYPE_STRING:
			return _failure_internal("INVALID_FILTER_DIFFICULTY", "difficulty filter must be a string.")
		var difficulty: String = str(difficulty_result.get("value", "")).strip_edges().to_lower()
		if not (difficulty in DIFFICULTIES):
			return _failure_internal("INVALID_FILTER_DIFFICULTY", "difficulty filter is unsupported.")
		result["has_difficulty"] = true
		result["difficulty"] = difficulty

	var daily_result: Dictionary = _read_optional_alias(source, ["daily", "is_daily", "daily_only"], "INVALID_FILTER_DAILY")
	if not bool(daily_result.get("ok", false)):
		return daily_result
	if bool(daily_result.get("present", false)):
		if typeof(daily_result.get("value", null)) != TYPE_BOOL:
			return _failure_internal("INVALID_FILTER_DAILY", "daily filter must be a boolean.")
		result["has_daily"] = true
		result["daily"] = bool(daily_result.get("value", false))

	var seed_result: Dictionary = _read_optional_alias(source, ["seed", "run_seed"], "INVALID_FILTER_SEED")
	if not bool(seed_result.get("ok", false)):
		return seed_result
	if bool(seed_result.get("present", false)):
		var seed_validation: Dictionary = _validate_nonnegative_integer(seed_result.get("value", null), "seed", "INVALID_FILTER_SEED")
		if not bool(seed_validation.get("ok", false)):
			return seed_validation
		result["has_seed"] = true
		result["seed"] = int(seed_validation.get("value", 0))
	return result


func _normalize_share_identity(
	seed_value: Variant,
	difficulty_value: Variant,
	ruleset_value: Variant,
	catalog_value: Variant
) -> Dictionary:
	var seed_validation: Dictionary = _validate_nonnegative_integer(seed_value, "seed", "INVALID_SHARE_SEED")
	if not bool(seed_validation.get("ok", false)):
		return seed_validation
	if typeof(difficulty_value) != TYPE_STRING:
		return _failure_internal("INVALID_SHARE_DIFFICULTY", "Share difficulty must be a string.")
	var difficulty: String = str(difficulty_value).strip_edges().to_lower()
	if not (difficulty in DIFFICULTIES):
		return _failure_internal("INVALID_SHARE_DIFFICULTY", "Share difficulty is unsupported.")
	var ruleset_validation: Dictionary = _validate_nonnegative_integer(ruleset_value, "ruleset_version", "INVALID_SHARE_RULESET")
	if not bool(ruleset_validation.get("ok", false)):
		return ruleset_validation
	var catalog_validation: Dictionary = _validate_nonnegative_integer(catalog_value, "catalog_version", "INVALID_SHARE_CATALOG")
	if not bool(catalog_validation.get("ok", false)):
		return catalog_validation
	return {
		"ok": true,
		"identity": {
			"seed": int(seed_validation.get("value", 0)),
			"difficulty": difficulty,
			"ruleset_version": int(ruleset_validation.get("value", 0)),
			"catalog_version": int(catalog_validation.get("value", 0)),
		},
	}


func _build_share_token(identity: Dictionary) -> String:
	var difficulty_code: String = str(_SHARE_DIFFICULTY_CODES.get(str(identity.get("difficulty", "")), ""))
	var seed_value: int = int(identity.get("seed", 0))
	var ruleset_value: int = int(identity.get("ruleset_version", 0))
	var catalog_value: int = int(identity.get("catalog_version", 0))
	return "%s%s%d%s%s%s%d%s%d%s%s" % [
		SHARE_TOKEN_PREFIX,
		SHARE_TOKEN_SEPARATOR,
		seed_value,
		SHARE_TOKEN_SEPARATOR,
		difficulty_code,
		SHARE_TOKEN_SEPARATOR,
		ruleset_value,
		SHARE_TOKEN_SEPARATOR,
		catalog_value,
		SHARE_TOKEN_SEPARATOR,
		_share_checksum(seed_value, str(identity.get("difficulty", "")), ruleset_value, catalog_value),
	]


func _share_checksum(
	seed_value: int,
	difficulty: String,
	ruleset_value: int,
	catalog_value: int
) -> String:
	var source: String = "%s|%d|%s|%d|%d" % [SHARE_TOKEN_DOMAIN, seed_value, difficulty, ruleset_value, catalog_value]
	return source.sha256_text().substr(0, SHARE_TOKEN_CHECKSUM_LENGTH)


func _parse_decimal_nonnegative(value: String) -> Dictionary:
	if value.is_empty():
		return _failure_internal("INVALID_DECIMAL", "A non-negative decimal value is required.")
	for index: int in range(value.length()):
		if not _is_ascii_digit(value.unicode_at(index)):
			return _failure_internal("INVALID_DECIMAL", "A decimal value must contain only digits.")
	var parsed: int = value.to_int()
	if parsed < 0 or "%d" % parsed != value:
		return _failure_internal("INVALID_DECIMAL", "The decimal value is outside the supported integer range or is not canonical.")
	return {"ok": true, "value": parsed}


# --- Generic validation helpers -------------------------------------------

func _read_optional_schema(source: Dictionary) -> Dictionary:
	var schema_result: Dictionary = _read_optional_alias(source, ["schema_version", "version"], "INVALID_SCHEMA_VERSION")
	if not bool(schema_result.get("ok", false)):
		return schema_result
	if bool(schema_result.get("present", false)):
		if not _is_integer_value(schema_result.get("value", null)):
			return _failure_internal("INVALID_SCHEMA_VERSION", "schema_version must be an integer.")
		if int(schema_result.get("value", -1)) < 0:
			return _failure_internal("INVALID_SCHEMA_VERSION", "schema_version cannot be negative.")
	return schema_result


func _read_required_nonnegative(
	source: Dictionary,
	keys: Array,
	field_name: String,
	error_code: String
) -> Dictionary:
	var result: Dictionary = _read_required_alias(source, keys, field_name, error_code)
	if not bool(result.get("ok", false)):
		return result
	return _validate_nonnegative_integer(result.get("value", null), field_name, error_code)


func _read_required_string(
	source: Dictionary,
	keys: Array,
	field_name: String,
	error_code: String
) -> Dictionary:
	var result: Dictionary = _read_required_alias(source, keys, field_name, error_code)
	if not bool(result.get("ok", false)):
		return result
	if typeof(result.get("value", null)) != TYPE_STRING:
		return _failure_internal(error_code, "%s must be a string." % field_name)
	return result


func _read_required_alias(
	source: Dictionary,
	keys: Array,
	field_name: String,
	error_code: String
) -> Dictionary:
	var result: Dictionary = _read_optional_alias(source, keys, error_code)
	if not bool(result.get("ok", false)):
		return result
	if not bool(result.get("present", false)):
		return _failure_internal(error_code, "%s is required." % field_name)
	return result


func _read_optional_alias(
	source: Dictionary,
	keys: Array,
	error_code: String
) -> Dictionary:
	var present: bool = false
	var selected: Variant = null
	for key: Variant in keys:
		if not source.has(key):
			continue
		if present and source.get(key, null) != selected:
			return _failure_internal(error_code, "Aliases for the same field disagree.")
		present = true
		selected = source.get(key, null)
	return {"ok": true, "present": present, "value": selected}


func _validate_nonnegative_integer(
	value: Variant,
	field_name: String,
	error_code: String
) -> Dictionary:
	if not _is_integer_value(value):
		return _failure_internal(error_code, "%s must be a non-negative integer." % field_name)
	var integer_value: int = int(value)
	if integer_value < 0:
		return _failure_internal(error_code, "%s cannot be negative." % field_name)
	return {"ok": true, "value": integer_value}


static func _is_integer_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number: float = value
	return is_finite(number) and floor(number) == number


func _validate_max_history(value: Variant) -> Dictionary:
	if not _is_integer_value(value):
		return _failure_internal("INVALID_MAX_HISTORY", "max_history must be an integer.")
	var requested: int = int(value)
	if requested < 1 or requested > MAX_HISTORY_LIMIT:
		return _failure_internal("INVALID_MAX_HISTORY", "max_history must be between 1 and %d." % MAX_HISTORY_LIMIT)
	return {"ok": true, "value": requested}


func _coerce_max_history(value: Variant) -> int:
	var validation: Dictionary = _validate_max_history(value)
	return int(validation.get("value", DEFAULT_MAX_HISTORY)) if bool(validation.get("ok", false)) else DEFAULT_MAX_HISTORY


func _evict_to_bound(records: Array, maximum: int) -> Array:
	var evicted: Array = []
	while records.size() > maximum:
		var removed: Variant = records.pop_front()
		if typeof(removed) == TYPE_DICTIONARY:
			evicted.append(str((removed as Dictionary).get("run_id", "")))
	return evicted


func _normalize_timestamps(source: Dictionary) -> Dictionary:
	var timestamps: Dictionary = {}
	var aliases: Dictionary = {
		"started_at": ["started_at", "created_at"],
		"completed_at": ["completed_at", "finished_at"],
	}
	for canonical_key: String in aliases.keys():
		var result: Dictionary = _read_optional_alias(source, aliases[canonical_key], "INVALID_TIMESTAMP")
		if not bool(result.get("ok", false)):
			return result
		if not bool(result.get("present", false)):
			continue
		var normalized: Dictionary = _normalize_timestamp_value(result.get("value", null), canonical_key)
		if not bool(normalized.get("ok", false)):
			return normalized
		timestamps[canonical_key] = normalized.get("value", null)

	if source.has("timestamp"):
		var timestamp_result: Dictionary = _normalize_timestamp_value(source.get("timestamp", null), "timestamp")
		if not bool(timestamp_result.get("ok", false)):
			return timestamp_result
		timestamps["timestamp"] = timestamp_result.get("value", null)
	return {"ok": true, "timestamps": timestamps}


func _normalize_timestamp_value(value: Variant, field_name: String) -> Dictionary:
	if typeof(value) == TYPE_STRING:
		var text: String = str(value).strip_edges()
		if text.is_empty() or text.length() > MAX_TIMESTAMP_LENGTH or _has_control_character(text):
			return _failure_internal("INVALID_TIMESTAMP", "%s must be a non-empty bounded string when textual." % field_name)
		return {"ok": true, "value": text}
	if typeof(value) == TYPE_INT:
		if int(value) < 0:
			return _failure_internal("INVALID_TIMESTAMP", "%s cannot be negative." % field_name)
		return {"ok": true, "value": int(value)}
	if typeof(value) == TYPE_FLOAT:
		var number: float = value
		if not is_finite(number) or number < 0.0:
			return _failure_internal("INVALID_TIMESTAMP", "%s must be a finite non-negative number." % field_name)
		# JSON parsers commonly materialize integral JSON numbers as floats.
		# Canonicalize those back to int so a numeric timestamp remains
		# idempotent after a JSON snapshot round trip.
		if floor(number) == number and number <= float(9223372036854775807):
			return {"ok": true, "value": int(number)}
		return {"ok": true, "value": number}
	return _failure_internal("INVALID_TIMESTAMP", "%s must be a string or non-negative number." % field_name)


func _derive_run_id(
	record: Dictionary,
	daily_id_present: bool,
	daily_id: Variant,
	daily_date_present: bool,
	daily_date: String
) -> String:
	var source: Array = [
		int(record.get("seed", 0)),
		str(record.get("difficulty", "")),
		int(record.get("ruleset_version", 0)),
		int(record.get("catalog_version", 0)),
		record.get("puzzle_ids", []) as Array,
		str(record.get("sequence_fingerprint", "")),
		bool(record.get("is_daily", false)),
		str(daily_id) if daily_id_present else "",
		daily_date if daily_date_present else "",
	]
	return "run_" + JSON.stringify(source).sha256_text().substr(0, 24)


static func _is_ascii_digit(character_code: int) -> bool:
	return character_code >= 48 and character_code <= 57


static func _is_hex_digit(character_code: int) -> bool:
	return (character_code >= 48 and character_code <= 57) \
		or (character_code >= 65 and character_code <= 70) \
		or (character_code >= 97 and character_code <= 102)


static func _has_control_character(value: String) -> bool:
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if code < 32 or code == 127:
			return true
	return false


static func _is_canonical_date_shape(value: String) -> bool:
	if value.length() != 10 or value.substr(4, 1) != "-" or value.substr(7, 1) != "-":
		return false
	for index: int in range(10):
		if index == 4 or index == 7:
			continue
		if not _is_ascii_digit(value.unicode_at(index)):
			return false
	return true


# --- Envelopes -------------------------------------------------------------

func _success(fields: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"success": true,
		"error": "",
		"error_code": "",
		"message": "",
	}
	for key: Variant in fields.keys():
		result[key] = fields[key]
	return result


func _failure(error_code: String, message: String) -> Dictionary:
	return {
		"success": false,
		"error": error_code,
		"error_code": error_code,
		"message": message,
	}


func _failure_from(value: Dictionary) -> Dictionary:
	return _failure(
		str(value.get("error_code", "RUN_HISTORY_ERROR")),
		str(value.get("message", "Run history operation failed."))
	)


func _failure_internal(error_code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error_code": error_code,
		"message": message,
	}
