extends GutTest

const AchievementPlatformClass = preload("res://scripts/AchievementPlatform.gd")
const AchievementServiceClass = preload("res://scripts/AchievementService.gd")


class FakePlayGames extends RefCounted:
	var received: Array = []

	func unlockAchievement(console_id: String) -> void:
		received.append(console_id)


func test_offline_adapter_queues_once_without_blocking_local_progress() -> void:
	var adapter: Node = AchievementPlatformClass.new()
	add_child_autoqfree(adapter)
	adapter.call("clear_pending_events")
	var first: bool = adapter.call("queue_unlock", "first_round_cleared", "event-1")
	var second: bool = adapter.call("queue_unlock", "first_round_cleared", "event-1")
	assert_true(first)
	assert_false(second)
	var status: Dictionary = adapter.call("get_status")
	assert_false(bool(status.get("available", true)))
	assert_eq(int(status.get("pending_count", 0)), 1)


func test_shipped_manifest_never_uses_a_local_id_as_a_console_placeholder() -> void:
	var adapter: Node = AchievementPlatformClass.new()
	add_child_autoqfree(adapter)
	var definitions: Array = AchievementServiceClass.get_definitions()
	assert_gt(definitions.size(), 0)
	for definition_value: Variant in definitions:
		var local_id: String = str((definition_value as Dictionary).get("id", ""))
		var console_id: String = str(adapter.call("resolve_console_id", local_id))
		assert_ne(console_id, local_id)


func test_unmapped_achievement_is_never_pushed_to_a_live_plugin() -> void:
	var adapter: Node = AchievementPlatformClass.new()
	add_child_autoqfree(adapter)
	adapter.call("clear_pending_events")
	var plugin: FakePlayGames = FakePlayGames.new()
	adapter.set("_play_games_singleton", plugin)
	adapter.set("is_available", true)
	adapter.set("_console_id_by_local", {"depth_five": "CggI-abcDEF"})
	adapter.call("queue_unlock", "depth_five", "event-mapped")
	adapter.call("queue_unlock", "depth_ten", "event-unmapped")
	assert_eq(plugin.received, ["CggI-abcDEF"])
	var pending: Array = adapter.call("get_pending_events")
	assert_eq(pending.size(), 1)
	assert_eq(str(pending[0].get("event_id", "")), "event-unmapped")


func test_flush_forwards_mapped_and_retains_unmapped() -> void:
	var adapter: Node = AchievementPlatformClass.new()
	add_child_autoqfree(adapter)
	adapter.call("clear_pending_events")
	adapter.call("queue_unlock", "streak_five", "event-a")
	adapter.call("queue_unlock", "archive_curator", "event-b")
	assert_eq((adapter.call("get_pending_events") as Array).size(), 2)
	var plugin: FakePlayGames = FakePlayGames.new()
	adapter.set("_play_games_singleton", plugin)
	adapter.set("is_available", true)
	adapter.set("_console_id_by_local", {"streak_five": "CggI-streakFIVE"})
	var flushed: int = adapter.call("flush")
	assert_eq(flushed, 1)
	assert_eq(plugin.received, ["CggI-streakFIVE"])
	var pending: Array = adapter.call("get_pending_events")
	assert_eq(pending.size(), 1)
	assert_eq(str(pending[0].get("event_id", "")), "event-b")


func test_flush_is_a_no_op_without_a_plugin() -> void:
	var adapter: Node = AchievementPlatformClass.new()
	add_child_autoqfree(adapter)
	adapter.call("clear_pending_events")
	adapter.call("queue_unlock", "boss_hunter", "event-c")
	assert_eq(int(adapter.call("flush")), 0)
	assert_eq((adapter.call("get_pending_events") as Array).size(), 1)
