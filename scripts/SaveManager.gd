extends Node
class_name SaveManagerService

const AchievementServiceClass = preload("res://scripts/AchievementService.gd")
const RunHistoryServiceClass = preload("res://scripts/RunHistoryService.gd")
const GachaServiceClass = preload("res://scripts/GachaService.gd")

## Persistent player profile for the GDD schema. Saves are small, explicit,
## and migrated from the previous save_data.json format when present.

const SAVE_PATH: String = "user://savegame.json"
const LEGACY_SAVE_PATH: String = "user://save_data.json"
const WEB_STORAGE_KEY: String = "mixing_flavors_savegame"
const WEB_BACKUP_STORAGE_KEY: String = "mixing_flavors_savegame_backup"

## Monotonic write counter and wall-clock stamp stored in every snapshot. They
## make the several storage authorities comparable: load picks the highest
## revision rather than the first non-empty source, so a stale localStorage
## entry can never silently outrank a newer on-disk save.
const REVISION_KEY: String = "revision"
const UPDATED_AT_KEY: String = "updated_at"

## Settings that used to be exposed as panel controls but had no consumer
## anywhere in the game. They are dropped while loading so an existing profile
## cannot resurrect a dead key. Append only; do not re-add a retired key.
const RETIRED_SETTING_KEYS: Array[String] = ["high_contrast"]

var data: Dictionary = {}
var path_override: String = ""

## Tracks the most recent write so a caller can tell the difference between
## "reward granted and stored" and "reward shown but lost on reload".
var last_save_succeeded: bool = true
var last_save_error: String = ""


func _ready() -> void:
	load_game()


## Persistence state for the HUD and for tests. `revision` only advances when a
## write actually reached both the file and the web mirror.
func get_persistence_status() -> Dictionary:
	return {
		"last_save_succeeded": last_save_succeeded,
		"last_save_error": last_save_error,
		"revision": int(data.get(REVISION_KEY, 0)),
		"updated_at": int(data.get(UPDATED_AT_KEY, 0)),
	}


func default_data() -> Dictionary:
	return {
		"version": 3,
		"player_stats": {
			"total_shards": 0,
			"gauntlet_max_depth": 0,
			"runs_completed": 0,
			"best_streak": 0,
			"gacha_epic_pity": 0,
			"gacha_legendary_pity": 0,
			"gacha_roll_count": 0,
			"gacha_next_seed": 0,
		},
		"inventory": [],
		"completion": {},
		"daily_results": {},
		"achievements": {},
		"run_history": {},
		"themes": ["Classic"],
		"trophies": [],
		REVISION_KEY: 0,
		UPDATED_AT_KEY: 0,
		"settings": {
			"sfx_vol": 1.0,
			"bgm_vol": 1.0,
			"haptics": true,
			"reduced_motion": false,
			"text_scale": 1.0,
			"tutorial_completed": false,
			"fullscreen": false,
		},
	}


func load_game() -> Dictionary:
	data = default_data()
	# Collect every authority and choose by revision, not by position. The
	# previous first-non-empty order let a stale localStorage entry outrank a
	# newer on-disk save, which silently rolled a player back.
	var candidates: Array[Dictionary] = [
		_read_save(WEB_STORAGE_KEY),
		_read_save(WEB_BACKUP_STORAGE_KEY),
		_read_file(_get_save_path()),
		_read_file(_get_backup_path()),
	]
	var chosen: Dictionary = {}
	var chosen_revision: int = -1
	for candidate: Dictionary in candidates:
		if candidate.is_empty():
			continue
		var revision: int = int(candidate.get(REVISION_KEY, 0))
		if revision > chosen_revision:
			chosen_revision = revision
			chosen = candidate
	if chosen.is_empty() and FileAccess.file_exists(LEGACY_SAVE_PATH):
		chosen = _migrate_legacy(_read_file(LEGACY_SAVE_PATH))
	_merge_data(chosen)
	if chosen.has(REVISION_KEY):
		data[REVISION_KEY] = int(chosen.get(REVISION_KEY, 0))
	if chosen.has(UPDATED_AT_KEY):
		data[UPDATED_AT_KEY] = int(chosen.get(UPDATED_AT_KEY, 0))
	_prune_retired_settings()
	return data.duplicate(true)


func save_game() -> bool:
	# Stamp the snapshot before serializing so the revision that lands on disk is
	# the revision the next load will compare against.
	data[REVISION_KEY] = int(data.get(REVISION_KEY, 0)) + 1
	data[UPDATED_AT_KEY] = int(Time.get_unix_time_from_system())
	var payload: String = JSON.stringify(data, "\t")
	var parsed: Variant = JSON.parse_string(payload)
	if not parsed is Dictionary:
		# A payload that cannot round-trip must not advance the revision.
		data[REVISION_KEY] = maxi(0, int(data.get(REVISION_KEY, 0)) - 1)
		push_warning("SaveManager refused to write an invalid snapshot")
		_record_save_failure("invalid_snapshot")
		return false
	var primary_path: String = _get_save_path()
	var backup_path: String = _get_backup_path()
	var temporary_path: String = primary_path + ".tmp"
	var directory: DirAccess = DirAccess.open(primary_path.get_base_dir())
	if directory == null:
		push_warning("SaveManager could not open save directory")
		data[REVISION_KEY] = maxi(0, int(data.get(REVISION_KEY, 0)) - 1)
		_record_save_failure("directory_unavailable")
		return false
	var temporary_file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if temporary_file == null:
		push_warning("SaveManager could not open temporary save %s" % temporary_path)
		data[REVISION_KEY] = maxi(0, int(data.get(REVISION_KEY, 0)) - 1)
		_record_save_failure("temporary_unavailable")
		return false
	temporary_file.store_string(payload)
	temporary_file.close()
	if directory.file_exists(primary_path.get_file()):
		if directory.file_exists(backup_path.get_file()):
			directory.remove(backup_path.get_file())
		if directory.rename(primary_path.get_file(), backup_path.get_file()) != OK:
			directory.remove(temporary_path.get_file())
			push_warning("SaveManager could not rotate the previous save")
			data[REVISION_KEY] = maxi(0, int(data.get(REVISION_KEY, 0)) - 1)
			_record_save_failure("rotation_failed")
			return false
	if directory.rename(temporary_path.get_file(), primary_path.get_file()) != OK:
		directory.remove(temporary_path.get_file())
		push_warning("SaveManager could not commit the new save")
		data[REVISION_KEY] = maxi(0, int(data.get(REVISION_KEY, 0)) - 1)
		_record_save_failure("commit_failed")
		return false
	# Mirror to the web authority. The previous good payload is rotated into the
	# backup key first, so the backup can actually recover a bad primary write;
	# writing the new payload to both keys made the backup worthless.
	_rotate_web_backup()
	var mirrored: bool = _save_web_copy(payload)
	if not mirrored:
		push_warning("SaveManager saved to disk but the web mirror failed; the next load may prefer the older web copy")
	# The file authority committed, so the revision stays advanced and the
	# in-memory profile is authoritative. Report the mirror failure honestly.
	last_save_succeeded = mirrored
	last_save_error = "" if mirrored else "web_mirror_failed"
	return true


func _record_save_failure(error_code: String) -> void:
	last_save_succeeded = false
	last_save_error = error_code


func get_player_stats() -> Dictionary:
	return _dictionary_value(data, "player_stats").duplicate(true)


func get_inventory() -> Array:
	var value: Variant = data.get("inventory", [])
	return value.duplicate(true) if value is Array else []


func get_completion() -> Dictionary:
	return _dictionary_value(data, "completion").duplicate(true)


func get_settings() -> Dictionary:
	return _dictionary_value(data, "settings").duplicate(true)


func get_daily_results() -> Dictionary:
	return _dictionary_value(data, "daily_results").duplicate(true)


func save_daily_results(results: Dictionary) -> bool:
	if results is Dictionary:
		data["daily_results"] = results.duplicate(true)
		return save_game()
	return false


func get_achievement_state() -> Dictionary:
	return _dictionary_value(data, "achievements").duplicate(true)


func record_achievement_event(event: Dictionary) -> Dictionary:
	var service: RefCounted = AchievementServiceClass.new()
	var load_result: Dictionary = service.call("load_state", get_achievement_state())
	if not bool(load_result.get("success", false)):
		return load_result
	var result: Dictionary = service.call("process_event", event)
	if bool(result.get("success", false)):
		data["achievements"] = service.call("get_state")
		if not save_game():
			return {
				"success": false,
				"error_code": "PERSISTENCE_FAILED",
				"message": "Achievement progress could not be saved.",
			}
		var platform: Node = get_node_or_null("/root/AchievementPlatform")
		if platform and platform.has_method("queue_achievement_event"):
			for achievement_id: Variant in (result.get("newly_unlocked", []) as Array):
				platform.call("queue_unlock", str(achievement_id), "local:%s" % str(achievement_id))
	return result


func get_run_history_state() -> Dictionary:
	return _dictionary_value(data, "run_history").duplicate(true)


func record_run_summary(summary: Dictionary) -> Dictionary:
	var service: RefCounted = RunHistoryServiceClass.new()
	var snapshot: Dictionary = get_run_history_state()
	if snapshot.is_empty():
		snapshot = {"schema_version": 1, "max_history": 20, "records": []}
	var load_result: Dictionary = service.call("load_snapshot", snapshot)
	if not bool(load_result.get("success", false)):
		return load_result
	var result: Dictionary = service.call("record_run", summary)
	if bool(result.get("success", false)):
		data["run_history"] = service.call("export_snapshot")
		save_game()
	return result


func get_latest_run() -> Dictionary:
	var snapshot: Dictionary = get_run_history_state()
	var records: Variant = snapshot.get("records", [])
	if records is Array and not (records as Array).is_empty():
		return (records as Array)[-1] as Dictionary
	return {}


func get_run_aggregates() -> Dictionary:
	var service: RefCounted = RunHistoryServiceClass.new()
	var snapshot: Dictionary = get_run_history_state()
	if snapshot.is_empty():
		snapshot = {"schema_version": 1, "max_history": 20, "records": []}
	var load_result: Dictionary = service.call("load_snapshot", snapshot)
	if not bool(load_result.get("success", false)):
		return {"best_score": 0, "best_depth": 0, "best_streak": 0}
	var aggregates: Dictionary = service.call("get_aggregates")
	return aggregates.duplicate(true)


func create_run_share_token(summary: Dictionary) -> Dictionary:
	var service: RefCounted = RunHistoryServiceClass.new()
	return service.call("encode_share_token", summary)


func decode_run_share_token(token: String) -> Dictionary:
	var service: RefCounted = RunHistoryServiceClass.new()
	return service.call("decode_share_token", token)


func get_themes() -> Array:
	var value: Variant = data.get("themes", [])
	return value.duplicate(true) if value is Array else ["Classic"]


func get_trophies() -> Array:
	var value: Variant = data.get("trophies", [])
	return value.duplicate(true) if value is Array else []


func unlock_theme(theme_name: String) -> bool:
	if theme_name.strip_edges().is_empty():
		return false
	var themes: Array = get_themes()
	if themes.has(theme_name):
		return false
	themes.append(theme_name)
	data["themes"] = themes
	return save_game()


func add_trophy(trophy_id: String) -> bool:
	if trophy_id.strip_edges().is_empty():
		return false
	var trophies: Array = get_trophies()
	if trophies.has(trophy_id):
		return false
	trophies.append(trophy_id)
	data["trophies"] = trophies
	return save_game()


func add_shards(amount: int) -> int:
	var snapshot: Dictionary = data.duplicate(true)
	var stats: Dictionary = _dictionary_value(data, "player_stats")
	var next_amount: int = maxi(0, int(stats.get("total_shards", 0)) + amount)
	stats["total_shards"] = next_amount
	data["player_stats"] = stats
	if not save_game():
		# The reward was not stored, so it must not be shown as banked. Restore
		# the profile and report the balance that actually survived.
		data = snapshot
		return maxi(0, int(_dictionary_value(data, "player_stats").get("total_shards", 0)))
	return next_amount


func record_puzzle_completion(puzzle_id: String, stars: int, best_time_seconds: float) -> Dictionary:
	if puzzle_id.is_empty():
		return {}
	var snapshot: Dictionary = data.duplicate(true)
	var completion: Dictionary = _dictionary_value(data, "completion")
	var previous: Dictionary = completion.get(puzzle_id, {}) if completion.get(puzzle_id, {}) is Dictionary else {}
	var next_stars: int = maxi(int(previous.get("stars", 0)), clampi(stars, 0, 3))
	var previous_time: float = float(previous.get("best_time_seconds", INF))
	var next_time: float = minf(previous_time, maxf(0.0, best_time_seconds))
	completion[puzzle_id] = {
		"stars": next_stars,
		"best_time_seconds": next_time,
	}
	data["completion"] = completion
	if not save_game():
		data = snapshot
		return {}
	return completion[puzzle_id].duplicate(true)


func record_run_result(depth_reached: int, completed: bool, best_streak: int) -> bool:
	var snapshot: Dictionary = data.duplicate(true)
	var stats: Dictionary = _dictionary_value(data, "player_stats")
	stats["gauntlet_max_depth"] = maxi(int(stats.get("gauntlet_max_depth", 0)), maxi(1, depth_reached))
	stats["best_streak"] = maxi(int(stats.get("best_streak", 0)), maxi(0, best_streak))
	if completed:
		stats["runs_completed"] = int(stats.get("runs_completed", 0)) + 1
	data["player_stats"] = stats
	if not save_game():
		data = snapshot
		return false
	return true


func set_setting(key: String, value: Variant) -> void:
	set_settings({key: value})


## Applies a batch of settings with a single durable write. The settings panel
## used to issue one set_setting per control, so closing it performed a full
## rotate/validate/mirror cycle for every value (twice, counting the panel's
## exit-tree save).
func set_settings(values: Dictionary) -> bool:
	if values.is_empty():
		return true
	var snapshot: Dictionary = data.duplicate(true)
	var settings: Dictionary = _dictionary_value(data, "settings")
	for key: Variant in values.keys():
		var setting_key: String = str(key)
		if setting_key.is_empty() or RETIRED_SETTING_KEYS.has(setting_key):
			# Retired settings are refused rather than stored, so a removed
			# control cannot reappear in a profile through a stale caller.
			continue
		settings[setting_key] = values[key]
	data["settings"] = settings
	if not save_game():
		data = snapshot
		return false
	return true


func get_or_create_gacha_seed() -> int:
	var stats: Dictionary = _dictionary_value(data, "player_stats")
	var seed_value: int = int(stats.get("gacha_next_seed", 0))
	if int(stats.get("gacha_roll_count", 0)) <= 0 and seed_value <= 0:
		seed_value = int(Time.get_unix_time_from_system()) & 0x7fffffff
		stats["gacha_next_seed"] = seed_value
		data["player_stats"] = stats
		save_game()
	return seed_value


func get_gacha_profile() -> Dictionary:
	var stats: Dictionary = _dictionary_value(data, "player_stats")
	var owned_ids: Array = []
	for item_value: Variant in get_inventory():
		if item_value is Dictionary:
			owned_ids.append(str((item_value as Dictionary).get("id", "")))
	return {
		"shards": int(stats.get("total_shards", 0)),
		"epic_pity": int(stats.get("gacha_epic_pity", 0)),
		"legendary_pity": int(stats.get("gacha_legendary_pity", 0)),
		"owned_item_ids": owned_ids,
		"roll_count": int(stats.get("gacha_roll_count", 0)),
	}


func apply_gacha_result(result: Dictionary) -> bool:
	if not bool(result.get("success", false)):
		return false
	# A roll must be applied exactly once. Without these guards a replayed or
	# stale result double-incremented the roll count and, because the seed is an
	# absolute assignment, rewound the deterministic seed chain.
	if not GachaServiceClass.is_supported_catalog_version(int(result.get("catalog_version", -1))):
		_record_save_failure("unsupported_catalog_version")
		return false
	var snapshot: Dictionary = data.duplicate(true)
	var stats: Dictionary = _dictionary_value(data, "player_stats")
	if int(stats.get("gacha_roll_count", 0)) > 0 and int(result.get("roll_seed", -1)) != int(stats.get("gacha_next_seed", 0)):
		# This result was computed from a seed the profile has already moved
		# past, so applying it would rewind the chain and re-issue an old reward.
		data = snapshot
		_record_save_failure("stale_roll")
		return false
	stats["total_shards"] = maxi(0, int(result.get("shards_balance", 0)))
	stats["gacha_epic_pity"] = clampi(
		int((result.get("pity_after", {}) as Dictionary).get("epic", 0)),
		0,
		GachaServiceClass.EPIC_PITY_LIMIT
	)
	stats["gacha_legendary_pity"] = clampi(
		int((result.get("pity_after", {}) as Dictionary).get("legendary", 0)),
		0,
		GachaServiceClass.LEGENDARY_PITY_LIMIT
	)
	stats["gacha_roll_count"] = maxi(0, int(stats.get("gacha_roll_count", 0)) + 1)
	stats["gacha_next_seed"] = maxi(0, int(result.get("seed", 0)))
	data["player_stats"] = stats
	if not bool(result.get("is_duplicate", false)):
		# Part of this same commit: a separate save here would make the shard
		# debit durable before the roll itself was atomic.
		add_inventory_item(str(result.get("item_id", "")), str(result.get("rarity", "common")), 1, false)
	if not save_game():
		# Roll the whole roll back. The UI must not tell the player the shards
		# were refunded while the debited balance is still in memory.
		data = snapshot
		return false
	return true


func add_inventory_item(item_id: String, rarity: String, mastery: int = 1, persist: bool = true) -> Dictionary:
	if item_id.is_empty():
		return {}
	var inventory: Array = get_inventory()
	for item: Variant in inventory:
		if item is Dictionary and str((item as Dictionary).get("id", "")) == item_id:
			var existing: Dictionary = item
			existing["mastery"] = maxi(int(existing.get("mastery", 0)), clampi(mastery, 1, 3))
			inventory[inventory.find(item)] = existing
			data["inventory"] = inventory
			if persist and not save_game():
				return {}
			return existing.duplicate(true)
	var item_data: Dictionary = {
		"id": item_id,
		"rarity": rarity.to_lower(),
		"mastery": clampi(mastery, 1, 3),
	}
	inventory.append(item_data)
	data["inventory"] = inventory
	if persist and not save_game():
		return {}
	return item_data.duplicate(true)


func _get_save_path() -> String:
	return path_override if not path_override.is_empty() else SAVE_PATH


func _get_backup_path() -> String:
	return _get_save_path() + ".backup"


func _is_web_runtime() -> bool:
	return OS.has_feature("web") and ClassDB.class_exists("JavaScriptBridge")


func _read_save(storage_key: String) -> Dictionary:
	if not _is_web_runtime():
		return {}
	var result: Variant = JavaScriptBridge.eval("window.localStorage.getItem('%s');" % storage_key)
	if typeof(result) != TYPE_STRING or str(result).is_empty():
		return {}
	var json: JSON = JSON.new()
	if json.parse(str(result)) != OK:
		return {}
	var parsed: Variant = json.data
	return parsed as Dictionary if parsed is Dictionary else {}


func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {}
	var parsed: Variant = json.data
	return parsed as Dictionary if parsed is Dictionary else {}


func _save_web_copy(payload: String) -> bool:
	if not _is_web_runtime():
		return true
	var encoded_payload: String = JSON.stringify(payload)
	# Synchronous eval (no global execution context) so the write's success or
	# failure is observable instead of being fire-and-forget. A quota or
	# private-mode rejection now surfaces as a failed mirror.
	var result: Variant = JavaScriptBridge.eval(
		"try { window.localStorage.setItem('%s', %s); true; } catch (error) { false; }" % [WEB_STORAGE_KEY, encoded_payload]
	)
	return bool(result)


## Copies the current web primary into the backup key before the primary is
## overwritten, so the backup holds the last known-good payload instead of a
## duplicate of the newest one.
func _rotate_web_backup() -> void:
	if not _is_web_runtime():
		return
	var previous: Variant = JavaScriptBridge.eval("window.localStorage.getItem('%s');" % WEB_STORAGE_KEY)
	if typeof(previous) != TYPE_STRING or str(previous).is_empty():
		return
	JavaScriptBridge.eval(
		"try { window.localStorage.setItem('%s', %s); } catch (error) {}" % [WEB_BACKUP_STORAGE_KEY, JSON.stringify(str(previous))]
	)


func _migrate_legacy(legacy: Dictionary) -> Dictionary:
	if legacy.is_empty():
		return {}
	var migrated: Dictionary = default_data()
	var completed: Variant = legacy.get("completed_puzzles", [])
	if completed is Array:
		for puzzle_id: Variant in completed:
			migrated["completion"][str(puzzle_id)] = {
				"stars": int(legacy.get("stars_earned", {}).get(str(puzzle_id), 0)) if legacy.get("stars_earned", {}) is Dictionary else 0,
				"best_time_seconds": float(legacy.get("best_times", {}).get(str(puzzle_id), 0.0)) if legacy.get("best_times", {}) is Dictionary else 0.0,
			}
	if legacy.get("settings", {}) is Dictionary:
		migrated["settings"].merge(legacy["settings"], true)
	return migrated


func _merge_data(incoming: Dictionary) -> void:
	if incoming.is_empty():
		return
	_merge_dictionary(data.get("player_stats", {}), incoming.get("player_stats", {}))
	_merge_dictionary(data.get("settings", {}), incoming.get("settings", {}), RETIRED_SETTING_KEYS)
	if incoming.has("inventory") and incoming["inventory"] is Array:
		data["inventory"] = (incoming["inventory"] as Array).duplicate(true)
	if incoming.has("completion") and incoming["completion"] is Dictionary:
		data["completion"] = (incoming["completion"] as Dictionary).duplicate(true)
	if incoming.has("daily_results") and incoming["daily_results"] is Dictionary:
		data["daily_results"] = (incoming["daily_results"] as Dictionary).duplicate(true)
	if incoming.has("achievements") and incoming["achievements"] is Dictionary:
		data["achievements"] = (incoming["achievements"] as Dictionary).duplicate(true)
	if incoming.has("run_history") and incoming["run_history"] is Dictionary:
		data["run_history"] = (incoming["run_history"] as Dictionary).duplicate(true)
	if incoming.has("themes") and incoming["themes"] is Array:
		data["themes"] = (incoming["themes"] as Array).duplicate(true)
	if incoming.has("trophies") and incoming["trophies"] is Array:
		data["trophies"] = (incoming["trophies"] as Array).duplicate(true)


func _merge_dictionary(target: Dictionary, source: Dictionary, retired_keys: Array = []) -> void:
	for key: Variant in source.keys():
		if retired_keys.has(key):
			continue
		target[key] = source[key]


func _prune_retired_settings() -> bool:
	var settings: Dictionary = _dictionary_value(data, "settings")
	var removed: bool = false
	for key: String in RETIRED_SETTING_KEYS:
		if settings.erase(key):
			removed = true
	if removed:
		data["settings"] = settings
	return removed


func _dictionary_value(container: Dictionary, key: String) -> Dictionary:
	var value: Variant = container.get(key, {})
	return value as Dictionary if value is Dictionary else {}
