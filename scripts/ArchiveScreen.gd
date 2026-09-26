extends Control
class_name ArchiveScreen

const GameManagerClass = preload("res://scripts/GameManager.gd")
const GachaServiceClass = preload("res://scripts/GachaService.gd")
const AchievementServiceClass = preload("res://scripts/AchievementService.gd")

## Name of the JavaScript global the injected clipboard code writes its result
## to. It is read back from GDScript so the UI only claims success when the
## browser actually resolved `navigator.clipboard.writeText`.
const WEB_COPY_STATE_KEY: String = "__mixingFlavorsWebCopyState"
const WEB_COPY_POLL_INTERVAL: float = 0.1
const WEB_COPY_TIMEOUT: float = 2.0

@onready var margin: MarginContainer = $Margin
@onready var shards_label: Label = $Margin/VBox/ShardsLabel
@onready var collection_label: Label = $Margin/VBox/CollectionLabel
@onready var completion_label: Label = $Margin/VBox/CompletionLabel
@onready var achievement_label: Label = $Margin/VBox/AchievementLabel
@onready var records_label: Label = $Margin/VBox/RecordsLabel
@onready var rates_label: Label = $Margin/VBox/RatesLabel
@onready var pity_label: Label = $Margin/VBox/PityLabel
@onready var mint_button: Button = $Margin/VBox/MintButton
@onready var mint_result_label: Label = $Margin/VBox/MintResultLabel
@onready var share_button: Button = $Margin/VBox/ShareButton
@onready var inventory_list: VBoxContainer = $Margin/VBox/Scroll/InventoryList
@onready var back_button: Button = $Margin/VBox/BackButton

var _web_copy_pending: bool = false
var _web_copy_token: String = ""
var _web_copy_elapsed: float = 0.0
var _web_copy_poll_accumulator: float = 0.0


func _ready() -> void:
	# The clipboard confirmation poll is the only reason this node needs
	# _process, and it must stay idle until a web copy is actually in flight.
	set_process(false)
	back_button.pressed.connect(_on_back_pressed)
	mint_button.pressed.connect(_on_mint_pressed)
	share_button.pressed.connect(_on_share_pressed)
	_style_action_buttons()
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager and save_manager.has_method("record_achievement_event"):
		save_manager.call("record_achievement_event", {"type": "archive_opened"})
		save_manager.call("record_achievement_event", {"type": "gacha_disclosure_viewed"})
	resized.connect(_apply_responsive_layout)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	call_deferred("_refresh_and_layout")


func _refresh_and_layout() -> void:
	_refresh()
	_apply_responsive_layout()


func _style_action_buttons() -> void:
	var back_normal := StyleBoxFlat.new()
	back_normal.bg_color = Color(0.16, 0.38, 0.72, 1.0)
	back_normal.corner_radius_top_left = 8
	back_normal.corner_radius_top_right = 8
	back_normal.corner_radius_bottom_left = 8
	back_normal.corner_radius_bottom_right = 8
	back_normal.content_margin_left = 16.0
	back_normal.content_margin_right = 16.0
	var back_hover := back_normal.duplicate(true) as StyleBoxFlat
	back_hover.bg_color = Color(0.24, 0.5, 0.86, 1.0)
	back_button.add_theme_stylebox_override("normal", back_normal)
	back_button.add_theme_stylebox_override("hover", back_hover)
	back_button.add_theme_stylebox_override("pressed", back_hover)
	var mint_normal := back_normal.duplicate(true) as StyleBoxFlat
	mint_normal.bg_color = Color(0.16, 0.38, 0.72, 1.0)
	var mint_hover := mint_normal.duplicate(true) as StyleBoxFlat
	mint_hover.bg_color = Color(0.24, 0.5, 0.86, 1.0)
	mint_button.add_theme_stylebox_override("normal", mint_normal)
	mint_button.add_theme_stylebox_override("hover", mint_hover)
	mint_button.add_theme_stylebox_override("pressed", mint_hover)
	share_button.add_theme_stylebox_override("normal", mint_normal)
	share_button.add_theme_stylebox_override("hover", mint_hover)
	share_button.add_theme_stylebox_override("pressed", mint_hover)


func _refresh() -> void:
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager == null:
		collection_label.text = "Profile unavailable"
		mint_button.disabled = true
		return
	var stats: Dictionary = save_manager.call("get_player_stats")
	var shards: int = int(stats.get("total_shards", 0))
	shards_label.text = "Voxel Shards: %d" % shards
	var best_score: int = 0
	var best_depth: int = int(stats.get("gauntlet_max_depth", 0))
	var best_streak: int = int(stats.get("best_streak", 0))
	if save_manager.has_method("get_run_aggregates"):
		var aggregates: Dictionary = save_manager.call("get_run_aggregates")
		best_score = maxi(best_score, int(aggregates.get("best_score", 0)))
		best_depth = maxi(best_depth, int(aggregates.get("best_depth", 0)))
		best_streak = maxi(best_streak, int(aggregates.get("best_streak", 0)))
	records_label.text = "Best score: %d  •  Depth: %d  •  Streak: %d" % [best_score, best_depth, best_streak]
	collection_label.text = "Archive entries: %d" % save_manager.call("get_inventory").size()
	var completion: Dictionary = save_manager.call("get_completion")
	var completed_count: int = 0
	for completion_value: Variant in completion.values():
		if completion_value is Dictionary and int((completion_value as Dictionary).get("stars", 0)) > 0:
			completed_count += 1
	completion_label.text = "Compendium completion: %d puzzles mastered" % completed_count
	if save_manager.has_method("get_achievement_state"):
		var achievement_state: Dictionary = save_manager.call("get_achievement_state")
		var unlocked_count: int = (achievement_state.get("unlocked_ids", []) as Array).size()
		var achievement_total: int = AchievementServiceClass.get_definitions().size()
		achievement_label.text = "Achievements: %d/%d unlocked" % [unlocked_count, achievement_total]
	# The guarantee fires at counter (limit - 1), so say so instead of implying
	# one more low-tier pull is still possible at "9/10".
	var epic_pity: int = int(stats.get("gacha_epic_pity", 0))
	var legendary_pity: int = int(stats.get("gacha_legendary_pity", 0))
	pity_label.text = "Epic pity %d/%d%s  •  Legendary pity %d/%d%s" % [
		epic_pity,
		GachaServiceClass.EPIC_PITY_LIMIT,
		"  (next pull guaranteed)" if epic_pity + 1 >= GachaServiceClass.EPIC_PITY_LIMIT else "",
		legendary_pity,
		GachaServiceClass.LEGENDARY_PITY_LIMIT,
		"  (next pull guaranteed)" if legendary_pity + 1 >= GachaServiceClass.LEGENDARY_PITY_LIMIT else "",
	]
	# The odds label is a dead node in the scene; drive it from the service so
	# the disclosed numbers cannot drift from the enforced selection buckets,
	# and state the pity guarantees rather than implying base rates.
	if rates_label != null:
		rates_label.text = "%s\n%s" % [GachaServiceClass.get_odds_disclosure(), GachaServiceClass.get_pity_disclosure()]
	mint_button.disabled = shards < GachaServiceClass.ROLL_COST_SHARDS
	mint_button.text = "Mint Voxel  •  %d Shards" % GachaServiceClass.ROLL_COST_SHARDS
	if save_manager.has_method("get_latest_run"):
		share_button.disabled = (save_manager.call("get_latest_run") as Dictionary).is_empty()
	else:
		share_button.disabled = true

	inventory_list.visible = true
	for child in inventory_list.get_children():
		child.queue_free()
	var inventory: Array = save_manager.call("get_inventory")
	if inventory.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "No sculptures collected yet. Clear a gauntlet round to earn shards."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_color_override("font_color", Color(0.25, 0.3, 0.38, 1.0))
		inventory_list.add_child(empty_label)
		return
	for item_value: Variant in inventory:
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var rarity: String = str(item.get("rarity", "common")).capitalize()
		var label: Label = Label.new()
		label.text = "%s  •  %s  •  Mastery %d" % [
			_format_item_name(str(item.get("id", "Unknown")), rarity),
			rarity,
			int(item.get("mastery", 1)),
		]
		# There is no mastery upgrade path in the shipped game, so do not imply
		# a progression the player cannot actually make.
		label.tooltip_text = "%s\n%s" % [
			_format_item_name(str(item.get("id", "Unknown")), rarity),
			rarity,
		]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 17)
		label.add_theme_color_override("font_color", _rarity_color(rarity))
		inventory_list.add_child(label)


func _on_mint_pressed() -> void:
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("get_gacha_profile"):
		mint_result_label.text = "Profile unavailable"
		return
	var stats: Dictionary = save_manager.call("get_player_stats")
	var profile: Dictionary = save_manager.call("get_gacha_profile")
	var service: RefCounted = GachaServiceClass.new()
	var seed_value: int = 0
	if save_manager.has_method("get_or_create_gacha_seed"):
		seed_value = int(save_manager.call("get_or_create_gacha_seed"))
	var result: Dictionary = service.call("roll", seed_value, GachaServiceClass.CURRENT_CATALOG_VERSION, profile)
	if not bool(result.get("success", false)):
		mint_result_label.text = str(result.get("message", result.get("error", "Roll failed")))
		return
	if save_manager.has_method("apply_gacha_result"):
		var applied: bool = bool(save_manager.call("apply_gacha_result", result))
		if not applied:
			# Do not claim a refund. Report the failure and let the verified
			# balance below speak for itself.
			mint_result_label.text = "The mint could not be saved. Your shard balance is unchanged."
			return
	var rarity: String = str(result.get("rarity", "Common"))
	var item_name: String = _format_item_name(str(result.get("item_id", "Unknown")), rarity)
	var duplicate_text: String = " (duplicate)" if bool(result.get("is_duplicate", false)) else ""
	var refund: int = int(result.get("shard_conversion", 0))
	var result_detail: String = "%s  •  %s%s" % [item_name, rarity, duplicate_text]
	if refund > 0:
		result_detail += "  •  +%d duplicate shards" % refund
	mint_result_label.text = result_detail
	_refresh()


func _on_share_pressed() -> void:
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("get_latest_run") or not save_manager.has_method("create_run_share_token"):
		return
	var latest: Dictionary = save_manager.call("get_latest_run")
	if latest.is_empty():
		return
	var share_result: Dictionary = save_manager.call("create_run_share_token", latest)
	if not bool(share_result.get("success", false)):
		mint_result_label.text = "This run cannot be shared yet."
		return
	var token: String = str(share_result.get("token", ""))
	var copied: bool = false
	# The native DisplayServer clipboard is a synchronous call, so a successful
	# return is a real copy. The web DisplayServer routes clipboard_set through
	# the same asynchronous, permission-gated navigator.clipboard API, so web
	# must never take this path: it is confirmed separately below or not at all.
	if not OS.has_feature("web") and DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(token)
		copied = true
	var web_copy_started: bool = _begin_web_clipboard_copy(token)
	if copied:
		mint_result_label.text = "Run code copied: %s" % token
	elif web_copy_started:
		mint_result_label.text = "Copying run code…"
	else:
		mint_result_label.text = "Copy this run code: %s" % token


func _begin_web_clipboard_copy(text: String) -> bool:
	# Returns true only when a web copy was actually requested. The confirmed
	# result arrives later through _process, which refuses to report success
	# unless the browser resolved the write.
	_clear_web_copy_state()
	if not OS.has_feature("web") or not ClassDB.class_exists("JavaScriptBridge"):
		return false
	if not _web_clipboard_supported():
		return false
	_web_copy_token = text
	_web_copy_elapsed = 0.0
	_web_copy_poll_accumulator = 0.0
	_web_copy_pending = true
	JavaScriptBridge.eval(_build_web_copy_script(text), true)
	set_process(true)
	return true


func _web_clipboard_supported() -> bool:
	var supported: Variant = JavaScriptBridge.eval(
		"typeof navigator !== 'undefined' && !!navigator.clipboard && typeof navigator.clipboard.writeText === 'function'",
		false
	)
	return bool(supported)


func _build_web_copy_script(text: String) -> String:
	var encoded_text: String = JSON.stringify(text)
	var key: String = WEB_COPY_STATE_KEY
	return (
		"window.%s = 'pending'; navigator.clipboard.writeText(%s).then("
		+ "function() { window.%s = 'copied'; },"
		+ "function() { window.%s = 'failed'; });"
	) % [key, encoded_text, key, key]


func _read_web_copy_state() -> String:
	var key: String = WEB_COPY_STATE_KEY
	var value: Variant = JavaScriptBridge.eval(
		"(typeof window !== 'undefined' && window.%s) ? window.%s : 'unknown'" % [key, key],
		false
	)
	return str(value) if typeof(value) == TYPE_STRING else "unknown"


func _process(delta: float) -> void:
	if not _web_copy_pending:
		set_process(false)
		return
	_web_copy_elapsed += delta
	_web_copy_poll_accumulator += delta
	if _web_copy_poll_accumulator < WEB_COPY_POLL_INTERVAL and _web_copy_elapsed < WEB_COPY_TIMEOUT:
		return
	_web_copy_poll_accumulator = 0.0
	var state: String = _read_web_copy_state()
	if state == "copied":
		_finish_web_copy(true)
	elif state == "failed" or _web_copy_elapsed >= WEB_COPY_TIMEOUT:
		# Denied permission, a missing API, or no answer at all: the copy cannot
		# be confirmed, so the status must not claim it happened.
		_finish_web_copy(false)


func _finish_web_copy(copied: bool) -> void:
	var token: String = _web_copy_token
	_clear_web_copy_state()
	if mint_result_label:
		if copied:
			mint_result_label.text = "Run code copied: %s" % token
		else:
			mint_result_label.text = "Copy this run code: %s" % token


func _clear_web_copy_state() -> void:
	_web_copy_pending = false
	_web_copy_token = ""
	_web_copy_elapsed = 0.0
	_web_copy_poll_accumulator = 0.0
	set_process(false)


func _on_back_pressed() -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("switch_mode"):
		game_manager.call("switch_mode", GameManagerClass.GameMode.MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _apply_responsive_layout() -> void:
	if not is_inside_tree() or margin == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var insets: Vector4 = _get_safe_area_insets(viewport_size)
	var display_size: Vector2 = _get_display_size()
	var ui_scale: float = _get_ui_scale(viewport_size, display_size)
	var available_height: float = maxf(1.0, display_size.y - insets.y - insets.w)
	var compact: bool = display_size.x < 700.0 or display_size.y < 620.0
	var horizontal: float = (16.0 if compact else 32.0) * ui_scale
	var top: float = (14.0 if compact else 24.0) * ui_scale
	var bottom: float = (14.0 if compact else 24.0) * ui_scale
	margin.offset_left = insets.x + horizontal
	margin.offset_top = insets.y + top
	margin.offset_right = -(insets.z + horizontal)
	margin.offset_bottom = -(insets.w + bottom)
	var vbox: VBoxContainer = margin.get_node_or_null("VBox") as VBoxContainer
	var scroll: ScrollContainer = margin.get_node_or_null("VBox/Scroll") as ScrollContainer
	if scroll:
		scroll.clip_contents = true
		scroll.custom_minimum_size = Vector2.ZERO
	if vbox:
		vbox.add_theme_constant_override("separation", int((6 if compact else 10) * ui_scale))
		var title: Label = vbox.get_node_or_null("Title") as Label
		if title:
			title.add_theme_font_size_override("font_size", int((30 if compact else 40) * ui_scale))
		for label_node: Control in [shards_label, collection_label, completion_label, achievement_label, records_label, rates_label, pity_label, mint_result_label]:
			if is_instance_valid(label_node):
				label_node.add_theme_font_size_override("font_size", int(17 * ui_scale))
		var rates: Label = vbox.get_node_or_null("RatesLabel") as Label
		var pity: Label = vbox.get_node_or_null("PityLabel") as Label
		if rates:
			rates.visible = display_size.y >= 300.0
		if pity:
			pity.visible = display_size.y >= 280.0
	if display_size.y < 450.0:
		# Keep progress/share information available in a short landscape
		# viewport. The scroll container owns overflow instead of permanently
		# hiding critical collection state.
		for label_node: Control in [collection_label, achievement_label, records_label, share_button, mint_result_label]:
			if is_instance_valid(label_node):
				label_node.visible = true
		for item_label: Control in inventory_list.get_children():
			if item_label is Label:
				(item_label as Label).visible = true
		inventory_list.visible = true
		if scroll:
			scroll.custom_minimum_size = Vector2(0.0, maxf(120.0, available_height - 170.0))
	mint_button.custom_minimum_size = Vector2(220.0 * ui_scale, 52.0 * ui_scale)
	share_button.custom_minimum_size = Vector2(220.0 * ui_scale, 48.0 * ui_scale)
	back_button.custom_minimum_size = Vector2(180.0 * ui_scale, (44.0 if compact else 50.0) * ui_scale)
	for item_label: Control in inventory_list.get_children():
		if item_label is Label:
			item_label.add_theme_font_size_override("font_size", int(17 * ui_scale))


func _format_item_name(item_id: String, rarity: String) -> String:
	var words: PackedStringArray = item_id.to_lower().replace("_", " ").split(" ")
	var filtered: Array[String] = []
	var rarity_prefix: String = rarity.to_lower()
	for word: String in words:
		if not word.is_empty() and word != rarity_prefix:
			filtered.append(word.capitalize())
	return " ".join(filtered) if not filtered.is_empty() else item_id


func _rarity_color(rarity: String) -> Color:
	match rarity.to_lower():
		"rare":
			return Color(0.12, 0.42, 0.85, 1.0)
		"epic":
			return Color(0.48, 0.22, 0.78, 1.0)
		"legendary":
			return Color(0.9, 0.42, 0.08, 1.0)
		_:
			return Color(0.25, 0.3, 0.38, 1.0)


func _get_display_size() -> Vector2:
	var window_size := Vector2(DisplayServer.window_get_size())
	return window_size if window_size.x > 0.0 and window_size.y > 0.0 else get_viewport_rect().size


func _get_ui_scale(viewport_size: Vector2, display_size: Vector2) -> float:
	if display_size.x <= 0.0 or display_size.y <= 0.0:
		return 1.0
	return clampf(maxf(viewport_size.x / display_size.x, viewport_size.y / display_size.y), 1.0, 4.0)


func _get_safe_area_insets(viewport_size: Vector2) -> Vector4:
	var minimum_insets: Vector4 = Vector4(12.0, 12.0, 12.0, 12.0)
	if DisplayServer.get_name() == "headless":
		return minimum_insets
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	if safe_area.size.x <= 0 or safe_area.size.y <= 0:
		return minimum_insets
	var window_size: Vector2 = Vector2(DisplayServer.window_get_size())
	var scale: Vector2 = Vector2.ONE
	if window_size.x > 0.0 and window_size.y > 0.0:
		scale = viewport_size / window_size
	var safe_min: Vector2 = Vector2(safe_area.position) * scale
	var safe_max: Vector2 = Vector2(safe_area.position + safe_area.size) * scale
	return Vector4(
		maxf(minimum_insets.x, safe_min.x),
		maxf(minimum_insets.y, safe_min.y),
		maxf(minimum_insets.z, viewport_size.x - safe_max.x),
		maxf(minimum_insets.w, viewport_size.y - safe_max.y)
	)
