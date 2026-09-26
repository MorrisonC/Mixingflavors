extends RefCounted
class_name DailyChallengeService

## Pure, optional Daily Challenge domain service.
##
## The service deliberately has no dependency on the clock, the network,
## notifications, or a save file.  Callers provide a UTC calendar date in the
## exact form `YYYY-MM-DD`; the caller is responsible for obtaining that date
## from its clock.  This keeps challenge identity reproducible offline and in
## headless tests.
##
## Identity API:
##   `derive_daily(utc_date, ruleset_version, catalog_version)` returns the
##   stable daily identity.  `daily_id` and `seed` are non-negative integers and
##   both include the date and both explicit versions in their input.
##
## Sequence API:
##   `create_daily_challenge(..., puzzle_selector)` asks the injected selector
##   for each round.  The canonical selector is a Callable accepting
##   `(seed: int, depth: int)` and returning either a puzzle ID String or a
##   puzzle Dictionary containing a non-empty `id`.  A selector with a third
##   argument receives `"endless"` as its difficulty, which lets
##   `PuzzleManager.get_puzzle_for_round` be injected without this service
##   duplicating catalog or puzzle-selection rules.  A one-argument selector
##   receives a context Dictionary instead.  The selector is responsible for
##   returning validated puzzle content; this service only validates the
##   returned ID and sequence shape.
##
## Local result API:
##   `record_result(..., result_data)` merges one attempt into the local record
##   for that exact date/ruleset/catalog identity.  Records contain
##   `completed`, `attempts`, `best_score`, `best_depth`, and `stars`.
##   Repeating the same result is idempotent by default.  Supplying a unique
##   `attempt_id` (in the method argument or result_data) intentionally counts
##   another attempt, including an otherwise identical result.  The service
##   stores a serializable snapshot; persistence can be delegated to the
##   existing profile store by the integrating layer.
##
## Catch-up API:
##   `get_catch_up_challenges(current_date, ruleset_version, catalog_version,
##   puzzle_selector, lookback_days)` returns the requested UTC date window in
##   ascending order.  It never expires a result, changes currency, or applies
##   a streak penalty.  `include_today` controls whether the current date is
##   included; the default keeps the normal daily challenge available while
##   still allowing prior dates to be played.
##
## Challenge, catch-up, and result operations return a Dictionary.  Success
## dictionaries contain `success: true` and `error_code: ""`; failures contain
## `success: false`, a stable `error_code`, and a human-readable `message`.
## The numeric get_daily_id()/get_daily_seed() helpers are the only exceptions
## and return -1 on invalid input.  No failed operation mutates the local result
## store.

const DEFAULT_SEQUENCE_LENGTH: int = 31
const MAX_SEQUENCE_LENGTH: int = 366
const DEFAULT_CATCH_UP_DAYS: int = 7
const MAX_CATCH_UP_DAYS: int = 3660
const RESULT_SCHEMA_VERSION: int = 1

const _IDENTITY_HASH_HEX_LENGTH: int = 12
const _DATE_MIN_YEAR: int = 1
const _DATE_MAX_YEAR: int = 9999
const _DAYS_FROM_0001_TO_1970: int = 719162
const _MAX_ATTEMPT_ID_LENGTH: int = 128

# The only mutable state is an in-memory, serializable result map.  A caller
# can replace or export this map through load_local_results()/get_local_results().
var _local_results: Dictionary = {}


## Derives the stable identity for one UTC date and explicit version pair.
## No current time is read.
func derive_daily(
	utc_date: Variant,
	ruleset_version: Variant,
	catalog_version: Variant
) -> Dictionary:
	var validation: Dictionary = _validate_identity_inputs(utc_date, ruleset_version, catalog_version)
	if not bool(validation.get("ok", false)):
		return _identity_failure(str(validation.get("error_code", "INVALID_IDENTITY")), str(validation.get("message", "Invalid daily identity.")))

	var date_info: Dictionary = validation.get("date", {})
	var date_value: String = str(date_info.get("utc_date", ""))
	var ruleset_value: int = int(validation.get("ruleset_version", 0))
	var catalog_value: int = int(validation.get("catalog_version", 0))
	var identity_source: String = "mixing_flavors_voxel_gauntlet|daily|%s|ruleset=%d|catalog=%d" % [
		date_value,
		ruleset_value,
		catalog_value,
	]
	var daily_id: int = _stable_nonnegative_hash(identity_source + "|id")
	var daily_key: String = "daily:%s:%d:%d" % [date_value, ruleset_value, catalog_value]

	return {
		"success": true,
		"error": "",
		"error_code": "",
		"message": "",
		"utc_date": date_value,
		"date": date_value,
		"day_index": int(date_info.get("day_index", 0)),
		"ruleset_version": ruleset_value,
		"catalog_version": catalog_value,
		"id": daily_id,
		"daily_id": daily_id,
		"seed": daily_id,
		"daily_seed": daily_id,
		"daily_key": daily_key,
		"daily_id_text": daily_key,
		"daily_id_string": daily_key,
	}


## Alias with an explicit identity-oriented name for callers that do not need
## to build a sequence.
func derive_daily_id(
	utc_date: Variant,
	ruleset_version: Variant,
	catalog_version: Variant
) -> Dictionary:
	return derive_daily(utc_date, ruleset_version, catalog_version)


## Numeric convenience accessors return -1 for malformed input.  Callers that
## need diagnostics should use derive_daily() instead of discarding its error
## envelope.
func get_daily_id(
	utc_date: Variant,
	ruleset_version: Variant,
	catalog_version: Variant
) -> int:
	var identity: Dictionary = derive_daily(utc_date, ruleset_version, catalog_version)
	return int(identity.get("daily_id", -1)) if bool(identity.get("success", false)) else -1


func get_daily_seed(
	utc_date: Variant,
	ruleset_version: Variant,
	catalog_version: Variant
) -> int:
	var identity: Dictionary = derive_daily(utc_date, ruleset_version, catalog_version)
	return int(identity.get("seed", -1)) if bool(identity.get("success", false)) else -1


## Returns true only for a canonical, real Gregorian UTC calendar date.
static func is_valid_utc_date(utc_date: Variant) -> bool:
	return bool(_parse_utc_date(utc_date).get("ok", false))


## Builds a complete challenge by delegating all puzzle selection to the
## injected selector.  Missing or invalid selectors fail closed rather than
## creating an interactive-looking challenge with fabricated puzzle content.
func create_daily_challenge(
	utc_date: Variant,
	ruleset_version: Variant,
	catalog_version: Variant,
	puzzle_selector: Variant = Callable(),
	sequence_length: Variant = DEFAULT_SEQUENCE_LENGTH
) -> Dictionary:
	var identity: Dictionary = derive_daily(utc_date, ruleset_version, catalog_version)
	if not bool(identity.get("success", false)):
		return identity

	var length_validation: Dictionary = _validate_sequence_length(sequence_length)
	if not bool(length_validation.get("ok", false)):
		return _merge_identity_failure(identity, length_validation)

	var selector_validation: Dictionary = _normalize_puzzle_selector(puzzle_selector)
	if not bool(selector_validation.get("ok", false)):
		return _merge_identity_failure(identity, selector_validation)

	var length: int = int(length_validation.get("sequence_length", 0))
	var selector: Callable = selector_validation.get("selector", Callable())
	var sequence_result: Dictionary = _select_sequence(
		identity,
		selector,
		length
	)
	if not bool(sequence_result.get("ok", false)):
		return _merge_identity_failure(identity, sequence_result)

	var challenge: Dictionary = identity.duplicate(true)
	var puzzle_ids: Array = sequence_result.get("puzzle_ids", []).duplicate()
	var puzzle_records: Array = sequence_result.get("puzzles", []).duplicate(true)
	challenge["sequence_length"] = length
	challenge["puzzle_ids"] = puzzle_ids
	challenge["sequence"] = puzzle_ids.duplicate()
	challenge["puzzles"] = puzzle_records
	challenge["sequence_fingerprint"] = str(sequence_result.get("fingerprint", ""))
	challenge["sequence_hash"] = str(sequence_result.get("fingerprint", ""))
	return challenge


## Short aliases for integration code.  They intentionally return the same
## failure envelopes and sequence contract as create_daily_challenge().
func create_challenge(
	utc_date: Variant,
	ruleset_version: Variant,
	catalog_version: Variant,
	puzzle_selector: Variant = Callable(),
	sequence_length: Variant = DEFAULT_SEQUENCE_LENGTH
) -> Dictionary:
	return create_daily_challenge(utc_date, ruleset_version, catalog_version, puzzle_selector, sequence_length)


func get_daily_challenge(
	utc_date: Variant,
	ruleset_version: Variant,
	catalog_version: Variant,
	puzzle_selector: Variant = Callable(),
	sequence_length: Variant = DEFAULT_SEQUENCE_LENGTH
) -> Dictionary:
	return create_daily_challenge(utc_date, ruleset_version, catalog_version, puzzle_selector, sequence_length)


## Returns a date-only catch-up window with local completion status.  This
## method does not need a selector and is useful for a menu that only wants to
## show which historical dates are available.
func get_catch_up_dates(
	current_date: Variant,
	ruleset_version: Variant,
	catalog_version: Variant,
	lookback_days: Variant = DEFAULT_CATCH_UP_DAYS,
	include_today: Variant = true
) -> Dictionary:
	var date_validation: Dictionary = _parse_utc_date(current_date)
	if not bool(date_validation.get("ok", false)):
		return _failure(
			str(date_validation.get("error_code", "INVALID_DATE")),
			str(date_validation.get("message", "Invalid UTC date."))
		)

	var ruleset_validation: Dictionary = _validate_version(ruleset_version, "ruleset_version", "INVALID_RULESET_VERSION")
	if not bool(ruleset_validation.get("ok", false)):
		return _failure(str(ruleset_validation.get("error_code", "INVALID_RULESET_VERSION")), str(ruleset_validation.get("message", "Invalid ruleset version.")))
	var catalog_validation: Dictionary = _validate_version(catalog_version, "catalog_version", "INVALID_CATALOG_VERSION")
	if not bool(catalog_validation.get("ok", false)):
		return _failure(str(catalog_validation.get("error_code", "INVALID_CATALOG_VERSION")), str(catalog_validation.get("message", "Invalid catalog version.")))

	var lookback_validation: Dictionary = _validate_catch_up_days(lookback_days)
	if not bool(lookback_validation.get("ok", false)):
		return _failure(str(lookback_validation.get("error_code", "INVALID_CATCH_UP_DAYS")), str(lookback_validation.get("message", "Invalid catch-up window.")))
	if typeof(include_today) != TYPE_BOOL:
		return _failure("INVALID_INCLUDE_TODAY", "include_today must be a boolean.")

	var date_count: int = int(lookback_validation.get("lookback_days", 0))
	var current_day: int = int(date_validation.get("day_index", 0))
	var start_day: int = current_day - date_count + (1 if bool(include_today) else 0)
	var end_day: int = current_day if bool(include_today) else current_day - 1
	if start_day < 0 or end_day < 0:
		return _failure("CATCH_UP_OUT_OF_RANGE", "The requested catch-up window starts before the supported UTC calendar range.")
	var dates: Array = []
	for day_value: int in range(start_day, end_day + 1):
		var date_value: String = _format_utc_date(day_value)
		var identity: Dictionary = derive_daily(date_value, ruleset_version, catalog_version)
		if not bool(identity.get("success", false)):
			return identity
		var record: Dictionary = _get_stored_record(int(identity.get("daily_id", -1)))
		dates.append({
			"utc_date": date_value,
			"date": date_value,
			"daily_id": int(identity.get("daily_id", -1)),
			"seed": int(identity.get("seed", -1)),
			"completed": bool(record.get("completed", false)),
			"record": record.duplicate(true),
		})

	return {
		"success": true,
		"error": "",
		"error_code": "",
		"message": "",
		"current_date": str(date_validation.get("utc_date", "")),
		"start_date": _format_utc_date(start_day),
		"end_date": _format_utc_date(end_day),
		"lookback_days": date_count,
		"include_today": bool(include_today),
		"dates": dates,
	}


## Builds catch-up challenges in ascending date order.  Completed dates remain
## available for replay/inspection; they are merely marked completed.  Missing
## historical dates are not treated as a failure or a streak event.
func get_catch_up_challenges(
	current_date: Variant,
	ruleset_version: Variant,
	catalog_version: Variant,
	puzzle_selector: Variant = Callable(),
	lookback_days: Variant = DEFAULT_CATCH_UP_DAYS,
	include_today: Variant = true
) -> Dictionary:
	var date_window: Dictionary = get_catch_up_dates(
		current_date,
		ruleset_version,
		catalog_version,
		lookback_days,
		include_today
	)
	if not bool(date_window.get("success", false)):
		return date_window

	var challenges: Array = []
	for date_entry: Variant in date_window.get("dates", []):
		if not date_entry is Dictionary:
			return _failure("INVALID_CATCH_UP_RESULT", "Catch-up date entry was malformed.")
		var entry: Dictionary = date_entry as Dictionary
		var challenge: Dictionary = create_daily_challenge(
			entry.get("utc_date", ""),
			ruleset_version,
			catalog_version,
			puzzle_selector,
			DEFAULT_SEQUENCE_LENGTH
		)
		if not bool(challenge.get("success", false)):
			return challenge
		challenge["completed"] = bool(entry.get("completed", false))
		challenge["pending"] = not bool(entry.get("completed", false))
		challenge["is_catch_up"] = str(entry.get("utc_date", "")) != str(date_window.get("current_date", ""))
		var existing_record: Dictionary = entry.get("record", {}) as Dictionary
		challenge["record"] = existing_record.duplicate(true)
		challenge["result"] = existing_record.duplicate(true)
		challenges.append(challenge)

	var result: Dictionary = date_window.duplicate(true)
	result["challenges"] = challenges
	return result


## Returns only catch-up challenges that have not been completed locally.
## It is a presentation convenience; it does not alter or expire any record.
func get_pending_catch_up_challenges(
	current_date: Variant,
	ruleset_version: Variant,
	catalog_version: Variant,
	puzzle_selector: Variant = Callable(),
	lookback_days: Variant = DEFAULT_CATCH_UP_DAYS,
	include_today: Variant = true
) -> Dictionary:
	var result: Dictionary = get_catch_up_challenges(
		current_date,
		ruleset_version,
		catalog_version,
		puzzle_selector,
		lookback_days,
		include_today
	)
	if not bool(result.get("success", false)):
		return result
	var pending: Array = []
	for challenge: Variant in result.get("challenges", []):
		if challenge is Dictionary and not bool((challenge as Dictionary).get("completed", false)):
			pending.append(challenge)
	result["challenges"] = pending
	result["pending_count"] = pending.size()
	return result


## Records or merges one local attempt.  `result_data` must contain:
##   completed: bool
##   score (or best_score): non-negative int
##   depth (or best_depth): non-negative int
##   stars: int in [0, 3]
## An optional `attempt_id` may be supplied either here or in result_data.
func record_result(
	utc_date: Variant,
	ruleset_version: Variant,
	catalog_version: Variant,
	result_data: Variant,
	attempt_id: Variant = ""
) -> Dictionary:
	var identity: Dictionary = derive_daily(utc_date, ruleset_version, catalog_version)
	if not bool(identity.get("success", false)):
		return identity

	var payload_validation: Dictionary = _validate_result_payload(result_data, identity, attempt_id)
	if not bool(payload_validation.get("ok", false)):
		return _merge_identity_failure(identity, payload_validation)

	var payload: Dictionary = payload_validation.get("payload", {})
	var key: String = str(identity.get("daily_id", "-1"))
	var existing: Dictionary = _get_stored_record(int(identity.get("daily_id", -1)))
	var attempt_key: String = str(payload.get("attempt_key", ""))
	var fingerprint: String = str(payload.get("fingerprint", ""))
	var attempt_keys: Dictionary = existing.get("attempt_keys", {}).duplicate(true) if existing.get("attempt_keys", {}) is Dictionary else {}

	if attempt_keys.has(attempt_key):
		var known_fingerprint: String = str(attempt_keys.get(attempt_key, ""))
		if known_fingerprint != fingerprint:
			return _merge_identity_failure(identity, {
				"ok": false,
				"error_code": "ATTEMPT_CONFLICT",
				"message": "The attempt_id was already used for a different result.",
			})
		var unchanged: Dictionary = _success_with_record(identity, existing, false, true)
		return unchanged

	var was_existing: bool = not existing.is_empty()
	if was_existing and str(payload.get("attempt_id", "")).is_empty() and str(existing.get("last_attempt_fingerprint", "")) == fingerprint:
		return _success_with_record(identity, existing, false, true)

	var record: Dictionary = existing.duplicate(true)
	record["schema_version"] = RESULT_SCHEMA_VERSION
	record["utc_date"] = str(identity.get("utc_date", ""))
	record["date"] = str(identity.get("utc_date", ""))
	record["day_index"] = int(identity.get("day_index", 0))
	record["ruleset_version"] = int(identity.get("ruleset_version", 0))
	record["catalog_version"] = int(identity.get("catalog_version", 0))
	record["id"] = int(identity.get("daily_id", -1))
	record["daily_id"] = int(identity.get("daily_id", -1))
	record["daily_key"] = str(identity.get("daily_key", ""))
	record["seed"] = int(identity.get("seed", -1))
	record["completed"] = bool(existing.get("completed", false)) or bool(payload.get("completed", false))
	record["attempts"] = int(existing.get("attempts", 0)) + 1
	record["best_score"] = maxi(int(existing.get("best_score", 0)), int(payload.get("score", 0)))
	record["best_depth"] = maxi(int(existing.get("best_depth", 0)), int(payload.get("depth", 0)))
	record["stars"] = maxi(int(existing.get("stars", 0)), int(payload.get("stars", 0)))
	record["score"] = int(record["best_score"])
	record["depth"] = int(record["best_depth"])
	record["last_attempt_fingerprint"] = fingerprint
	attempt_keys[attempt_key] = fingerprint
	record["attempt_keys"] = attempt_keys
	_local_results[key] = record.duplicate(true)
	return _success_with_record(identity, record, true, false)


## Returns a result envelope for the exact daily identity.  `found` is false
## when the date has no local record; an empty record is never fabricated.
func get_result(
	utc_date: Variant,
	ruleset_version: Variant,
	catalog_version: Variant
) -> Dictionary:
	var identity: Dictionary = derive_daily(utc_date, ruleset_version, catalog_version)
	if not bool(identity.get("success", false)):
		return identity
	var record: Dictionary = _get_stored_record(int(identity.get("daily_id", -1)))
	var result: Dictionary = identity.duplicate(true)
	result["found"] = not record.is_empty()
	result["record"] = record.duplicate(true)
	result["result"] = record.duplicate(true)
	result["completed"] = bool(record.get("completed", false))
	result["attempts"] = int(record.get("attempts", 0))
	result["best_score"] = int(record.get("best_score", 0))
	result["best_depth"] = int(record.get("best_depth", 0))
	result["stars"] = int(record.get("stars", 0))
	result["score"] = int(record.get("best_score", 0))
	result["depth"] = int(record.get("best_depth", 0))
	return result


func get_local_result(
	utc_date: Variant,
	ruleset_version: Variant,
	catalog_version: Variant
) -> Dictionary:
	return get_result(utc_date, ruleset_version, catalog_version)


## Exports a JSON-serializable local result snapshot.  The integrating profile
## layer can store this dictionary and later pass it to load_local_results().
func get_local_results() -> Dictionary:
	return {
		"schema_version": RESULT_SCHEMA_VERSION,
		"results": _local_results.duplicate(true),
	}


func export_local_results() -> Dictionary:
	return get_local_results()


## Replaces local results transactionally from either the exported wrapper or
## a raw `{daily_id: record}` map.  Malformed snapshots are rejected without
## partially changing the current store.
func load_local_results(snapshot: Variant) -> Dictionary:
	if typeof(snapshot) != TYPE_DICTIONARY:
		return _failure("INVALID_RESULTS", "Local results must be a dictionary.")
	var source: Dictionary = snapshot as Dictionary
	if source.has("schema_version"):
		var schema_value: Variant = source.get("schema_version", -1)
		if not _is_integer_value(schema_value) or int(schema_value) != RESULT_SCHEMA_VERSION:
			return _failure("INVALID_RESULTS_SCHEMA", "Unsupported local results schema version.")
	var records_value: Variant = source.get("results", source)
	if typeof(records_value) != TYPE_DICTIONARY:
		return _failure("INVALID_RESULTS", "Local results must contain a results dictionary.")
	var records: Dictionary = records_value as Dictionary
	var working: Dictionary = {}
	for raw_key: Variant in records.keys():
		var raw_record: Variant = records.get(raw_key, null)
		var normalized: Dictionary = _normalize_stored_record(raw_record)
		if not bool(normalized.get("ok", false)):
			return _failure(
				"INVALID_RESULT_RECORD",
				"Malformed local result for '%s': %s" % [str(raw_key), str(normalized.get("message", "unknown error"))]
			)
		var normalized_record: Dictionary = normalized.get("record", {})
		var record_key: String = str(int(normalized_record.get("daily_id", -1)))
		if working.has(record_key):
			return _failure("DUPLICATE_RESULT_RECORD", "Local results contain duplicate daily records.")
		working[record_key] = normalized_record
	_local_results = working
	return {
		"success": true,
		"error": "",
		"error_code": "",
		"message": "",
		"count": working.size(),
	}


func load_results(snapshot: Variant) -> Dictionary:
	return load_local_results(snapshot)


## Internal helpers ---------------------------------------------------------

static func _identity_failure(error_code: String, message: String) -> Dictionary:
	return {
		"success": false,
		"error": error_code,
		"error_code": error_code,
		"message": message,
		"utc_date": "",
		"date": "",
		"day_index": -1,
		"ruleset_version": -1,
		"catalog_version": -1,
		"id": -1,
		"daily_id": -1,
		"seed": -1,
		"daily_seed": -1,
		"daily_key": "",
		"daily_id_text": "",
		"daily_id_string": "",
	}


func _merge_identity_failure(identity: Dictionary, failure: Dictionary) -> Dictionary:
	var result: Dictionary = identity.duplicate(true)
	result["success"] = false
	result["error"] = str(failure.get("error_code", "DAILY_CHALLENGE_ERROR"))
	result["error_code"] = str(result["error"])
	result["message"] = str(failure.get("message", "Daily challenge operation failed."))
	return result


func _success_with_record(
	identity: Dictionary,
	record: Dictionary,
	changed: bool,
	idempotent: bool
) -> Dictionary:
	var result: Dictionary = identity.duplicate(true)
	result["changed"] = changed
	result["idempotent"] = idempotent
	result["found"] = true
	result["record"] = record.duplicate(true)
	result["result"] = record.duplicate(true)
	result["completed"] = bool(record.get("completed", false))
	result["attempts"] = int(record.get("attempts", 0))
	result["best_score"] = int(record.get("best_score", 0))
	result["best_depth"] = int(record.get("best_depth", 0))
	result["stars"] = int(record.get("stars", 0))
	result["score"] = int(record.get("best_score", 0))
	result["depth"] = int(record.get("best_depth", 0))
	return result


func _failure(error_code: String, message: String) -> Dictionary:
	return {
		"success": false,
		"error": error_code,
		"error_code": error_code,
		"message": message,
	}


func _validate_identity_inputs(
	utc_date: Variant,
	ruleset_version: Variant,
	catalog_version: Variant
) -> Dictionary:
	var date_validation: Dictionary = _parse_utc_date(utc_date)
	if not bool(date_validation.get("ok", false)):
		return date_validation
	var ruleset_validation: Dictionary = _validate_version(ruleset_version, "ruleset_version", "INVALID_RULESET_VERSION")
	if not bool(ruleset_validation.get("ok", false)):
		return ruleset_validation
	var catalog_validation: Dictionary = _validate_version(catalog_version, "catalog_version", "INVALID_CATALOG_VERSION")
	if not bool(catalog_validation.get("ok", false)):
		return catalog_validation
	return {
		"ok": true,
		"date": date_validation,
		"ruleset_version": int(ruleset_validation.get("version", 0)),
		"catalog_version": int(catalog_validation.get("version", 0)),
	}


## JSON parsers may materialize integral JSON numbers as floats.  Accept only
## finite, exactly integral floats so persisted local records remain readable
## without weakening malformed-input checks.
static func _is_integer_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number: float = value
	return is_finite(number) and floor(number) == number


func _validate_version(value: Variant, field_name: String, error_code: String) -> Dictionary:
	if not _is_integer_value(value):
		return {"ok": false, "error_code": error_code, "message": "%s must be a non-negative integer." % field_name}
	var version: int = int(value)
	if version < 0:
		return {"ok": false, "error_code": error_code, "message": "%s cannot be negative." % field_name}
	return {"ok": true, "version": version}


func _validate_sequence_length(value: Variant) -> Dictionary:
	if not _is_integer_value(value):
		return {"ok": false, "error_code": "INVALID_SEQUENCE_LENGTH", "message": "sequence_length must be an integer."}
	var length: int = int(value)
	if length < 1 or length > MAX_SEQUENCE_LENGTH:
		return {
			"ok": false,
			"error_code": "INVALID_SEQUENCE_LENGTH",
			"message": "sequence_length must be between 1 and %d." % MAX_SEQUENCE_LENGTH,
		}
	return {"ok": true, "sequence_length": length}


func _validate_catch_up_days(value: Variant) -> Dictionary:
	if not _is_integer_value(value):
		return {"ok": false, "error_code": "INVALID_CATCH_UP_DAYS", "message": "lookback_days must be an integer."}
	var days: int = int(value)
	if days < 1 or days > MAX_CATCH_UP_DAYS:
		return {
			"ok": false,
			"error_code": "INVALID_CATCH_UP_DAYS",
			"message": "lookback_days must be between 1 and %d." % MAX_CATCH_UP_DAYS,
		}
	return {"ok": true, "lookback_days": days}


static func _parse_utc_date(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_STRING:
		return {"ok": false, "error_code": "INVALID_DATE", "message": "UTC date must be a YYYY-MM-DD string."}
	var date_value: String = value
	if date_value.length() != 10 or date_value.substr(4, 1) != "-" or date_value.substr(7, 1) != "-":
		return {"ok": false, "error_code": "INVALID_DATE", "message": "UTC date must use YYYY-MM-DD format."}
	for index: int in range(10):
		if index == 4 or index == 7:
			continue
		if not _is_ascii_digit(date_value.unicode_at(index)):
			return {"ok": false, "error_code": "INVALID_DATE", "message": "UTC date must use YYYY-MM-DD format."}
	var year: int = int(date_value.substr(0, 4))
	var month: int = int(date_value.substr(5, 2))
	var day: int = int(date_value.substr(8, 2))
	if year < _DATE_MIN_YEAR or year > _DATE_MAX_YEAR:
		return {"ok": false, "error_code": "INVALID_DATE", "message": "UTC year must be between 0001 and 9999."}
	if month < 1 or month > 12:
		return {"ok": false, "error_code": "INVALID_DATE", "message": "UTC month must be between 01 and 12."}
	var maximum_day: int = _days_in_month(year, month)
	if day < 1 or day > maximum_day:
		return {"ok": false, "error_code": "INVALID_DATE", "message": "UTC day is not valid for the supplied month."}
	var day_index: int = _days_from_civil(year, month, day) + _DAYS_FROM_0001_TO_1970
	if _format_utc_date(day_index) != date_value:
		return {"ok": false, "error_code": "INVALID_DATE", "message": "UTC date is not canonical."}
	return {
		"ok": true,
		"utc_date": date_value,
		"year": year,
		"month": month,
		"day": day,
		"day_index": day_index,
	}


static func _is_ascii_digit(character_code: int) -> bool:
	return character_code >= 48 and character_code <= 57


static func _is_leap_year(year: int) -> bool:
	return year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)


static func _days_in_month(year: int, month: int) -> int:
	match month:
		2:
			return 29 if _is_leap_year(year) else 28
		4, 6, 9, 11:
			return 30
		_:
			return 31


## Gregorian civil-date conversion.  It is intentionally implemented here
## rather than using an engine clock/date helper so date arithmetic remains
## pure and UTC is explicit in the API.
static func _days_from_civil(year: int, month: int, day: int) -> int:
	var adjusted_year: int = year - 1 if month <= 2 else year
	var era: int = floori(float(adjusted_year) / 400.0)
	var year_of_era: int = adjusted_year - era * 400
	var shifted_month: int = month - 3 if month > 2 else month + 9
	var day_of_year: int = floori((153.0 * float(shifted_month) + 2.0) / 5.0) + day - 1
	var day_of_era: int = (
		year_of_era * 365
		+ floori(float(year_of_era) / 4.0)
		- floori(float(year_of_era) / 100.0)
		+ day_of_year
	)
	return era * 146097 + day_of_era - 719468


static func _format_utc_date(day_index: int) -> String:
	var z_value: int = day_index + 306
	var era: int = floori(float(z_value) / 146097.0)
	var day_of_era: int = z_value - era * 146097
	var year_of_era: int = floori(
		(
			float(day_of_era)
			- floori(float(day_of_era) / 1460.0)
			+ floori(float(day_of_era) / 36524.0)
			- floori(float(day_of_era) / 146096.0)
		) / 365.0
	)
	var year: int = year_of_era + era * 400
	var day_of_year: int = day_of_era - (
		365 * year_of_era
		+ floori(float(year_of_era) / 4.0)
		- floori(float(year_of_era) / 100.0)
	)
	var shifted_month: int = floori((5.0 * float(day_of_year) + 2.0) / 153.0)
	var day: int = day_of_year - floori((153.0 * float(shifted_month) + 2.0) / 5.0) + 1
	var month: int = shifted_month + 3 if shifted_month < 10 else shifted_month - 9
	if month <= 2:
		year += 1
	return "%04d-%02d-%02d" % [year, month, day]


func _normalize_puzzle_selector(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_CALLABLE:
		var callable_value: Callable = value
		if not callable_value.is_valid():
			return {"ok": false, "error_code": "INVALID_PUZZLE_SELECTOR", "message": "puzzle_selector Callable is not valid."}
		return {"ok": true, "selector": callable_value}
	if typeof(value) == TYPE_OBJECT and value != null:
		var object_value: Object = value
		if object_value.has_method("get_puzzle_for_round"):
			var object_selector: Callable = Callable(object_value, "get_puzzle_for_round")
			if object_selector.is_valid():
				return {"ok": true, "selector": object_selector}
	return {
		"ok": false,
		"error_code": "INVALID_PUZZLE_SELECTOR",
		"message": "puzzle_selector must be a valid Callable or expose get_puzzle_for_round().",
	}


func _select_sequence(identity: Dictionary, selector: Callable, sequence_length: int) -> Dictionary:
	var puzzle_ids: Array = []
	var puzzles: Array = []
	var argument_count: int = selector.get_argument_count()
	if argument_count == 0 or argument_count > 3:
		return {
			"ok": false,
			"error_code": "INVALID_PUZZLE_SELECTOR",
			"message": "puzzle_selector must accept two arguments, or one context argument.",
		}
	var seed_value: int = int(identity.get("seed", 0))
	for depth: int in range(1, sequence_length + 1):
		var selected: Variant = null
		if argument_count == 1:
			selected = selector.call({
				"utc_date": str(identity.get("utc_date", "")),
				"date": str(identity.get("date", "")),
				"ruleset_version": int(identity.get("ruleset_version", 0)),
				"catalog_version": int(identity.get("catalog_version", 0)),
				"daily_id": int(identity.get("daily_id", -1)),
				"seed": seed_value,
				"daily_seed": seed_value,
				"depth": depth,
				"round": depth,
				"sequence_length": sequence_length,
				"difficulty": "endless",
			})
		elif argument_count >= 3:
			selected = selector.call(seed_value, depth, "endless")
		else:
			selected = selector.call(seed_value, depth)

		var selected_validation: Dictionary = _validate_selected_puzzle(selected)
		if not bool(selected_validation.get("ok", false)):
			selected_validation["depth"] = depth
			return selected_validation
		var selected_id: String = str(selected_validation.get("puzzle_id", ""))
		var selected_puzzle: Dictionary = selected_validation.get("puzzle", {})
		puzzle_ids.append(selected_id)
		puzzles.append(selected_puzzle)

	return {
		"ok": true,
		"puzzle_ids": puzzle_ids,
		"puzzles": puzzles,
		"fingerprint": _fingerprint_sequence(puzzle_ids),
	}


func _validate_selected_puzzle(value: Variant) -> Dictionary:
	var puzzle_id: String = ""
	var puzzle: Dictionary = {}
	if typeof(value) == TYPE_STRING:
		puzzle_id = value
		puzzle = {"id": puzzle_id}
	elif value is Dictionary:
		puzzle = (value as Dictionary).duplicate(true)
		var raw_id: Variant = puzzle.get("id", null)
		if typeof(raw_id) != TYPE_STRING:
			return {"ok": false, "error_code": "INVALID_PUZZLE_SELECTION", "message": "Selected puzzle id must be a string."}
		puzzle_id = raw_id
	else:
		return {"ok": false, "error_code": "INVALID_PUZZLE_SELECTION", "message": "Puzzle selector must return a string id or dictionary."}

	if puzzle_id.strip_edges().is_empty() or puzzle_id != puzzle_id.strip_edges():
		return {"ok": false, "error_code": "INVALID_PUZZLE_SELECTION", "message": "Selected puzzle id must be non-empty and canonical."}
	return {"ok": true, "puzzle_id": puzzle_id, "puzzle": puzzle}


func _fingerprint_sequence(puzzle_ids: Array) -> String:
	return JSON.stringify(puzzle_ids).sha256_text()


func _validate_result_payload(
	value: Variant,
	identity: Dictionary,
	attempt_id_value: Variant
) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "error_code": "INVALID_RESULT", "message": "result_data must be a dictionary."}
	var raw: Dictionary = value as Dictionary
	var completed_value: Variant = raw.get("completed", null)
	if typeof(completed_value) != TYPE_BOOL:
		return {"ok": false, "error_code": "INVALID_RESULT", "message": "result_data.completed must be a boolean."}

	var score_validation: Dictionary = _read_nonnegative_metric(raw, "score", "best_score")
	if not bool(score_validation.get("ok", false)):
		return score_validation
	var depth_validation: Dictionary = _read_nonnegative_metric(raw, "depth", "best_depth")
	if not bool(depth_validation.get("ok", false)):
		return depth_validation
	var stars_value: Variant = raw.get("stars", null)
	if not _is_integer_value(stars_value):
		return {"ok": false, "error_code": "INVALID_RESULT", "message": "result_data.stars must be an integer."}
	var stars: int = int(stars_value)
	if stars < 0 or stars > 3:
		return {"ok": false, "error_code": "INVALID_RESULT", "message": "result_data.stars must be between 0 and 3."}

	var supplied_attempt_id: String = ""
	if raw.has("attempt_id"):
		var raw_attempt_value: Variant = raw.get("attempt_id", null)
		if typeof(raw_attempt_value) != TYPE_STRING or str(raw_attempt_value).is_empty():
			return {"ok": false, "error_code": "INVALID_ATTEMPT_ID", "message": "result_data.attempt_id must be a non-empty string."}
		supplied_attempt_id = raw_attempt_value
	if typeof(attempt_id_value) != TYPE_STRING:
		return {"ok": false, "error_code": "INVALID_ATTEMPT_ID", "message": "attempt_id must be a non-empty string."}
	if not str(attempt_id_value).is_empty():
		var argument_attempt_id: String = attempt_id_value
		if not supplied_attempt_id.is_empty() and supplied_attempt_id != argument_attempt_id:
			return {"ok": false, "error_code": "INVALID_ATTEMPT_ID", "message": "The two supplied attempt_id values do not match."}
		supplied_attempt_id = argument_attempt_id
	if supplied_attempt_id.length() > _MAX_ATTEMPT_ID_LENGTH:
		return {"ok": false, "error_code": "INVALID_ATTEMPT_ID", "message": "attempt_id is too long."}

	var identity_check: Dictionary = _validate_optional_result_identity(raw, identity)
	if not bool(identity_check.get("ok", false)):
		return identity_check

	var score: int = int(score_validation.get("value", 0))
	var depth: int = int(depth_validation.get("value", 0))
	var fingerprint: String = "%s|%d|%d|%d|%d|%d|%d" % [
		str(identity.get("daily_id", -1)),
		1 if completed_value else 0,
		score,
		depth,
		stars,
		int(identity.get("seed", -1)),
		int(identity.get("daily_id", -1)),
	]
	var attempt_key: String = supplied_attempt_id if not supplied_attempt_id.is_empty() else "payload:%s" % fingerprint
	return {
		"ok": true,
		"payload": {
			"completed": completed_value,
			"score": score,
			"depth": depth,
			"stars": stars,
			"attempt_id": supplied_attempt_id,
			"attempt_key": attempt_key,
			"fingerprint": fingerprint,
		},
	}


func _read_nonnegative_metric(raw: Dictionary, primary_key: String, alias_key: String) -> Dictionary:
	var has_primary: bool = raw.has(primary_key)
	var has_alias: bool = raw.has(alias_key)
	if not has_primary and not has_alias:
		return {"ok": false, "error_code": "INVALID_RESULT", "message": "result_data.%s is required." % primary_key}
	var primary_value: Variant = raw.get(primary_key, null)
	var alias_value: Variant = raw.get(alias_key, null)
	if has_primary and not _is_integer_value(primary_value):
		return {"ok": false, "error_code": "INVALID_RESULT", "message": "result_data.%s must be a non-negative integer." % primary_key}
	if has_alias and not _is_integer_value(alias_value):
		return {"ok": false, "error_code": "INVALID_RESULT", "message": "result_data.%s must be a non-negative integer." % alias_key}
	if has_primary and int(primary_value) < 0:
		return {"ok": false, "error_code": "INVALID_RESULT", "message": "result_data.%s cannot be negative." % primary_key}
	if has_alias and int(alias_value) < 0:
		return {"ok": false, "error_code": "INVALID_RESULT", "message": "result_data.%s cannot be negative." % alias_key}
	if has_primary and has_alias and int(primary_value) != int(alias_value):
		return {"ok": false, "error_code": "INVALID_RESULT", "message": "result_data %s aliases disagree." % primary_key}
	return {"ok": true, "value": int(primary_value) if has_primary else int(alias_value)}


func _validate_optional_result_identity(raw: Dictionary, identity: Dictionary) -> Dictionary:
	var has_date_field: bool = raw.has("utc_date") or raw.has("date")
	if has_date_field:
		var date_value: Variant = raw.get("utc_date", raw.get("date", null))
		if raw.has("utc_date") and raw.has("date") and str(raw.get("utc_date", "")) != str(raw.get("date", "")):
			return {"ok": false, "error_code": "RESULT_IDENTITY_MISMATCH", "message": "Result date fields do not match."}
		if typeof(date_value) != TYPE_STRING or str(date_value) != str(identity.get("utc_date", "")):
			return {"ok": false, "error_code": "RESULT_IDENTITY_MISMATCH", "message": "Result date does not match the requested daily challenge."}
	for field: String in ["ruleset_version", "catalog_version", "daily_id", "seed"]:
		if raw.has(field):
			var field_value: Variant = raw.get(field, null)
			if not _is_integer_value(field_value):
				return {"ok": false, "error_code": "RESULT_IDENTITY_MISMATCH", "message": "Result %s must be an integer." % field}
			if int(field_value) != int(identity.get(field, -1)):
				return {"ok": false, "error_code": "RESULT_IDENTITY_MISMATCH", "message": "Result %s does not match the requested daily challenge." % field}
	return {"ok": true}


func _get_stored_record(daily_id: int) -> Dictionary:
	var value: Variant = _local_results.get(str(daily_id), {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _normalize_stored_record(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "message": "record is not a dictionary."}
	var raw: Dictionary = value as Dictionary
	var date_value: Variant = raw.get("utc_date", raw.get("date", null))
	var date_validation: Dictionary = _parse_utc_date(date_value)
	if not bool(date_validation.get("ok", false)):
		return {"ok": false, "message": str(date_validation.get("message", "invalid date"))}
	var ruleset_value: Variant = raw.get("ruleset_version", null)
	var catalog_value: Variant = raw.get("catalog_version", null)
	var ruleset_validation: Dictionary = _validate_version(ruleset_value, "ruleset_version", "INVALID_RULESET_VERSION")
	if not bool(ruleset_validation.get("ok", false)):
		return {"ok": false, "message": str(ruleset_validation.get("message", "invalid ruleset version"))}
	var catalog_validation: Dictionary = _validate_version(catalog_value, "catalog_version", "INVALID_CATALOG_VERSION")
	if not bool(catalog_validation.get("ok", false)):
		return {"ok": false, "message": str(catalog_validation.get("message", "invalid catalog version"))}

	var completed_value: Variant = raw.get("completed", null)
	var attempts_value: Variant = raw.get("attempts", null)
	var best_score_value: Variant = raw.get("best_score", raw.get("score", null))
	var best_depth_value: Variant = raw.get("best_depth", raw.get("depth", null))
	var stars_value: Variant = raw.get("stars", null)
	if typeof(completed_value) != TYPE_BOOL or not _is_integer_value(attempts_value) or not _is_integer_value(best_score_value) or not _is_integer_value(best_depth_value) or not _is_integer_value(stars_value):
		return {"ok": false, "message": "record metrics have invalid types."}
	if raw.has("score") and not _is_integer_value(raw.get("score", null)):
		return {"ok": false, "message": "record score must be an integer."}
	if raw.has("depth") and not _is_integer_value(raw.get("depth", null)):
		return {"ok": false, "message": "record depth must be an integer."}
	if raw.has("best_score") and raw.has("score") and int(raw.get("best_score", 0)) != int(raw.get("score", 0)):
		return {"ok": false, "message": "record score aliases disagree."}
	if raw.has("best_depth") and raw.has("depth") and int(raw.get("best_depth", 0)) != int(raw.get("depth", 0)):
		return {"ok": false, "message": "record depth aliases disagree."}
	if int(attempts_value) < 1 or int(best_score_value) < 0 or int(best_depth_value) < 0 or int(stars_value) < 0 or int(stars_value) > 3:
		return {"ok": false, "message": "record metrics are outside their allowed ranges."}

	var identity: Dictionary = derive_daily(
		date_value,
		int(ruleset_value),
		int(catalog_value)
	)
	if not bool(identity.get("success", false)):
		return {"ok": false, "message": "record identity could not be derived."}
	if raw.has("daily_id") and (not _is_integer_value(raw.get("daily_id", null)) or int(raw.get("daily_id", -1)) != int(identity.get("daily_id", -2))):
		return {"ok": false, "message": "record daily_id does not match its date and versions."}
	if raw.has("seed") and (not _is_integer_value(raw.get("seed", null)) or int(raw.get("seed", -1)) != int(identity.get("seed", -2))):
		return {"ok": false, "message": "record seed does not match its date and versions."}

	var normalized: Dictionary = {
		"schema_version": RESULT_SCHEMA_VERSION,
		"utc_date": str(identity.get("utc_date", "")),
		"date": str(identity.get("utc_date", "")),
		"day_index": int(identity.get("day_index", 0)),
		"ruleset_version": int(identity.get("ruleset_version", 0)),
		"catalog_version": int(identity.get("catalog_version", 0)),
		"id": int(identity.get("daily_id", -1)),
		"daily_id": int(identity.get("daily_id", -1)),
		"daily_key": str(identity.get("daily_key", "")),
		"seed": int(identity.get("seed", -1)),
		"completed": completed_value,
		"attempts": int(attempts_value),
		"best_score": int(best_score_value),
		"best_depth": int(best_depth_value),
		"stars": int(stars_value),
		"score": int(best_score_value),
		"depth": int(best_depth_value),
	}
	if raw.has("last_attempt_fingerprint"):
		var fingerprint_value: Variant = raw.get("last_attempt_fingerprint", null)
		if typeof(fingerprint_value) != TYPE_STRING or str(fingerprint_value).is_empty():
			return {"ok": false, "message": "last_attempt_fingerprint is invalid."}
		normalized["last_attempt_fingerprint"] = fingerprint_value
	if raw.has("attempt_keys"):
		var attempt_keys_value: Variant = raw.get("attempt_keys", null)
		if typeof(attempt_keys_value) != TYPE_DICTIONARY:
			return {"ok": false, "message": "attempt_keys must be a dictionary."}
		var attempt_keys: Dictionary = {}
		for key_value: Variant in (attempt_keys_value as Dictionary).keys():
			var fingerprint_value: Variant = (attempt_keys_value as Dictionary).get(key_value, null)
			if typeof(key_value) != TYPE_STRING or str(key_value).is_empty() or typeof(fingerprint_value) != TYPE_STRING or str(fingerprint_value).is_empty():
				return {"ok": false, "message": "attempt_keys contains an invalid entry."}
			attempt_keys[str(key_value)] = str(fingerprint_value)
		normalized["attempt_keys"] = attempt_keys
	return {"ok": true, "record": normalized}


static func _stable_nonnegative_hash(source: String) -> int:
	# Twelve hexadecimal digits fit safely in Godot's signed 64-bit integer and
	# avoid exposing a platform-dependent signed RNG seed.
	return source.sha256_text().substr(0, _IDENTITY_HASH_HEX_LENGTH).hex_to_int()
