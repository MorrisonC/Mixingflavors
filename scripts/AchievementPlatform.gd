extends Node
class_name AchievementPlatformAdapter

## Optional boundary for Google Play Games v2.
##
## The pure AchievementService remains authoritative. This node only translates
## already-committed local unlock events to an Android plugin when one is
## present. It deliberately queues events on Web, desktop, denied auth, and
## service outages so offline play never depends on a network call.

signal availability_changed(available: bool, reason: String)
signal event_queued(event_id: String)

const MAX_PENDING_EVENTS: int = 100
const PLATFORM_MANIFEST_PATH: String = "res://data/achievements/google_play_manifest.json"

var is_available: bool = false
var is_initialized: bool = false
var status_reason: String = "not_initialized"
var _pending_events: Array[Dictionary] = []
var _queued_ids: Dictionary = {}
var _play_games_singleton: Object = null
var _console_id_by_local: Dictionary = {}


func _ready() -> void:
	initialize()


func initialize() -> Dictionary:
	is_initialized = true
	_play_games_singleton = null
	if OS.has_feature("android") and Engine.has_singleton("PlayGames"):
		_play_games_singleton = Engine.get_singleton("PlayGames")
	_console_id_by_local = _load_console_ids()
	if is_instance_valid(_play_games_singleton):
		is_available = true
		if _console_id_by_local.is_empty():
			status_reason = "plugin_available_awaiting_console_ids"
		else:
			status_reason = "plugin_available"
	else:
		is_available = false
		status_reason = "offline_or_plugin_unavailable"
	if DisplayServer.get_name() != "headless":
		_queue_persisted_unlocks()
	availability_changed.emit(is_available, status_reason)
	return get_status()


## Reads the reviewable manifest and keeps only entries that already have a real
## Play Console id. Blank ids are intentionally dropped so a local snake_case id
## can never be pushed to a live plugin as if it were a Console resource.
func _load_console_ids() -> Dictionary:
	var mapped: Dictionary = {}
	if not FileAccess.file_exists(PLATFORM_MANIFEST_PATH):
		return mapped
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLATFORM_MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Achievement manifest is not a JSON object; no Console ids mapped")
		return mapped
	var document: Dictionary = parsed as Dictionary
	for entry: Variant in (document.get("achievements", []) as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var local_id: String = str(entry.get("local_id", "")).strip_edges().to_lower()
		var console_id: String = str(entry.get("play_games_id", "")).strip_edges()
		if not local_id.is_empty() and not console_id.is_empty():
			mapped[local_id] = console_id
	return mapped


## Returns the Play Console resource id, or an empty string when the local id is
## not registered yet. Unmapped achievements stay queued rather than failing.
func resolve_console_id(local_achievement_id: String) -> String:
	return str(_console_id_by_local.get(local_achievement_id.strip_edges().to_lower(), ""))


func _can_forward() -> bool:
	return (
		is_available
		and is_instance_valid(_play_games_singleton)
		and _play_games_singleton.has_method("unlockAchievement")
	)


func _queue_persisted_unlocks() -> void:
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("get_achievement_state"):
		return
	var state: Dictionary = save_manager.call("get_achievement_state")
	for achievement_id: Variant in (state.get("unlocked_ids", []) as Array):
		queue_unlock(str(achievement_id), "sync:%s" % str(achievement_id))


func get_status() -> Dictionary:
	return {
		"available": is_available,
		"initialized": is_initialized,
		"reason": status_reason,
		"pending_count": _pending_events.size(),
		"mapped_count": _console_id_by_local.size(),
		"manifest_path": PLATFORM_MANIFEST_PATH,
	}


func queue_achievement_event(event: Dictionary) -> bool:
	if not is_initialized:
		initialize()
	var event_id: String = str(event.get("event_id", "")).strip_edges()
	if event_id.is_empty():
		event_id = "event:%d" % _pending_events.size()
	if _queued_ids.has(event_id):
		return false
	var queued: Dictionary = event.duplicate(true)
	queued["event_id"] = event_id
	_queued_ids[event_id] = true
	_pending_events.append(queued)
	while _pending_events.size() > MAX_PENDING_EVENTS:
		var evicted: Dictionary = _pending_events.pop_front()
		_queued_ids.erase(str(evicted.get("event_id", "")))
	if _can_forward():
		var console_id: String = resolve_console_id(str(queued.get("achievement_id", "")))
		if not console_id.is_empty():
			_play_games_singleton.call("unlockAchievement", console_id)
			_pending_events.pop_back()
			_queued_ids.erase(event_id)
	event_queued.emit(event_id)
	return true


func queue_unlock(local_achievement_id: String, event_id: String = "") -> bool:
	var normalized_id: String = local_achievement_id.strip_edges().to_lower()
	if normalized_id.is_empty():
		return false
	var queue_event: Dictionary = {
		"event_id": event_id if not event_id.is_empty() else "unlock:%s" % normalized_id,
		"achievement_id": normalized_id,
		"type": "unlock",
	}
	return queue_achievement_event(queue_event)


func flush() -> int:
	if not _can_forward():
		return 0
	var flushed: int = 0
	var unmapped: Array[Dictionary] = []
	for event: Dictionary in _pending_events:
		var console_id: String = resolve_console_id(str(event.get("achievement_id", event.get("event_id", ""))))
		if console_id.is_empty():
			unmapped.append(event)
			continue
		_play_games_singleton.call("unlockAchievement", console_id)
		_queued_ids.erase(str(event.get("event_id", "")))
		flushed += 1
	_pending_events = unmapped
	return flushed


func clear_pending_events() -> void:
	_pending_events.clear()
	_queued_ids.clear()


func get_pending_events() -> Array[Dictionary]:
	return _pending_events.duplicate(true)
