extends Control

signal start_next_nonogram_requested
signal leave_requested
signal replay_requested
signal new_run_requested
signal share_requested

## Name of the JavaScript global the injected clipboard code writes its result
## to. It is read back from GDScript so the UI only claims success when the
## browser actually resolved `navigator.clipboard.writeText`.
const WEB_COPY_STATE_KEY: String = "__mixingFlavorsWebCopyState"
const WEB_COPY_POLL_INTERVAL: float = 0.1
const WEB_COPY_TIMEOUT: float = 2.0

@onready var header_label: Label = $Background/PanelContainer/VBoxContainer/HeaderLabel
@onready var clock_label: Label = $Background/PanelContainer/VBoxContainer/ClockPanel/ClockLabel
@onready var subtitle_label: Label = get_node_or_null("Background/PanelContainer/VBoxContainer/SubtitleLabel") as Label
@onready var context_label: Label = get_node_or_null("Background/PanelContainer/VBoxContainer/ContextLabel") as Label
@onready var stars_container: HBoxContainer = $Background/PanelContainer/VBoxContainer/IllustrationContainer/OverlayBox/VBoxContainer/StarsContainer
@onready var radial_meter: TextureProgressBar = $Background/PanelContainer/VBoxContainer/MeterContainer/TextureProgressBar
@onready var time_stat_label: Label = $Background/PanelContainer/VBoxContainer/StatsContainer/TimeRow/Value
@onready var score_stat_label: Label = $Background/PanelContainer/VBoxContainer/StatsContainer/ScoreRow/Value
@onready var stars_stat_label: Label = $Background/PanelContainer/VBoxContainer/StatsContainer/StarsRow/Value
@onready var best_stat_label: Label = get_node_or_null("Background/PanelContainer/VBoxContainer/StatsContainer/BestRow/Value") as Label
@onready var seed_stat_label: Label = get_node_or_null("Background/PanelContainer/VBoxContainer/StatsContainer/SeedRow/Value") as Label
@onready var share_status_label: Label = get_node_or_null("Background/PanelContainer/VBoxContainer/ShareStatusLabel") as Label
@onready var action_row: GridContainer = get_node_or_null("Background/PanelContainer/VBoxContainer/ActionRow") as GridContainer
@onready var replay_button: Button = get_node_or_null("Background/PanelContainer/VBoxContainer/ActionRow/ReplayButton") as Button
@onready var new_run_button: Button = get_node_or_null("Background/PanelContainer/VBoxContainer/ActionRow/NewRunButton") as Button
@onready var share_button: Button = get_node_or_null("Background/PanelContainer/VBoxContainer/ActionRow/ShareButton") as Button
@onready var next_button: Button = $Background/PanelContainer/VBoxContainer/NextButton
@onready var leave_button: Button = $Background/PanelContainer/VBoxContainer/LeaveButton
@onready var confetti_particles: CPUParticles2D = $ConfettiParticles
@onready var card: PanelContainer = $Background/PanelContainer
@onready var card_content: VBoxContainer = $Background/PanelContainer/VBoxContainer
@onready var meter_container: Control = $Background/PanelContainer/VBoxContainer/MeterContainer
@onready var illustration_container: Control = $Background/PanelContainer/VBoxContainer/IllustrationContainer

var is_endless_gauntlet: bool = false
var result_context: String = "standalone"
var _next_transition_pending: bool = false
var _pending_stats: Variant = null
var _has_pending_stats: bool = false
var _applied_result: Dictionary = {}
var _share_code: String = ""
var _share_copy_in_progress: bool = false
var _web_copy_pending: bool = false
var _web_copy_code: String = ""
var _web_copy_elapsed: float = 0.0
var _web_copy_poll_accumulator: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The clipboard confirmation poll is the only reason this node needs
	# _process, and it must stay idle until a web copy is actually in flight.
	set_process(false)
	if leave_button:
		leave_button.pressed.connect(_on_leave_pressed)
	if next_button:
		next_button.pressed.connect(_on_next_pressed)
	if replay_button:
		replay_button.pressed.connect(_on_replay_pressed)
	if new_run_button:
		new_run_button.pressed.connect(_on_new_run_pressed)
	if share_button:
		share_button.pressed.connect(_on_share_pressed)
	_detect_endless_context()
	resized.connect(_apply_responsive_layout)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")
	call_deferred("_focus_primary_action")
	if _has_pending_stats:
		_apply_result_stats(_pending_stats)


func set_result_context(context: String) -> void:
	result_context = context.strip_edges().to_lower()
	if result_context.is_empty():
		result_context = "standalone"
	if is_node_ready():
		_detect_endless_context()
		_apply_responsive_layout()


func set_share_code(code: String) -> void:
	_share_code = code.strip_edges()
	if share_button:
		share_button.disabled = _share_code.is_empty()
		share_button.tooltip_text = "Copy replay code" if not _share_code.is_empty() else "Replay code unavailable"
	if share_status_label:
		share_status_label.text = ""


func get_result_snapshot() -> Dictionary:
	return _applied_result.duplicate(true)


func _detect_endless_context() -> void:
	var candidate: Node = get_parent()
	while candidate != null:
		if candidate.name == "EscapeGauntlet" or candidate.has_method("get_next_puzzle_for_mode"):
			is_endless_gauntlet = true
			break
		candidate = candidate.get_parent()
	if is_endless_gauntlet or result_context == "gauntlet":
		is_endless_gauntlet = true
		result_context = "gauntlet"
	elif result_context != "compendium":
		is_endless_gauntlet = false
	_update_context_copy()


func _update_context_copy() -> void:
	if is_endless_gauntlet or result_context == "gauntlet":
		if next_button:
			next_button.text = "Continue Gauntlet"
			next_button.tooltip_text = "Continue to the next endless round"
		if replay_button:
			replay_button.text = "Retry Seed"
			replay_button.tooltip_text = "Restart this gauntlet with the same seed"
		if new_run_button:
			new_run_button.show()
			new_run_button.text = "New Run"
	elif result_context == "compendium":
		if next_button:
			next_button.text = "Back to Compendium"
			next_button.tooltip_text = "Choose another puzzle"
		if replay_button:
			replay_button.text = "Retry Puzzle"
			replay_button.tooltip_text = "Try this puzzle again"
		if new_run_button:
			new_run_button.hide()
	else:
		if next_button:
			next_button.text = "Continue"
			next_button.tooltip_text = "Continue"
		if replay_button:
			replay_button.text = "Retry"
			replay_button.tooltip_text = "Try this puzzle again"
		if new_run_button:
			new_run_button.hide()
	if share_status_label:
		share_status_label.text = ""


func initialize(stats: Variant) -> void:
	# GridManager can create this scene from an async win callback. In that
	# path @onready references are not guaranteed to exist until the next tree
	# notification, so retain the payload and apply it from _ready().
	_pending_stats = stats
	_has_pending_stats = true
	if is_node_ready() and header_label != null:
		_apply_result_stats(stats)
		_has_pending_stats = false


func _apply_result_stats(stats: Variant) -> void:
	var level_name: String = str(_read_first_stat(stats, ["current_level_string", "level_name", "puzzle_name"], "Puzzle complete"))
	if level_name.strip_edges().is_empty():
		level_name = "Puzzle complete"
	if header_label:
		header_label.text = level_name

	var total_seconds: float = maxf(0.0, float(_read_first_stat(stats, ["time_seconds", "time", "elapsed_seconds"], 0.0)))
	var total_seconds_int: int = int(floor(total_seconds))
	var minutes: int = int(total_seconds_int / 60)
	var seconds: int = total_seconds_int % 60
	var time_string: String = "%02d:%02d" % [minutes, seconds]
	if clock_label:
		clock_label.text = time_string
	if time_stat_label:
		time_stat_label.text = time_string

	var score_value: int = maxi(0, int(float(_read_first_stat(stats, ["raw_score", "score", "total_score"], 0))))
	if score_stat_label:
		score_stat_label.text = _format_number_with_commas(score_value)

	var stars_earned: int = clampi(int(float(_read_first_stat(stats, ["stars_earned", "stars"], 0))), 0, 3)
	if stars_stat_label:
		stars_stat_label.text = str(stars_earned) + "/3"

	if stars_container:
		for index in range(stars_container.get_child_count()):
			var star_icon: Node = stars_container.get_child(index)
			if star_icon is Label:
				var star_label: Label = star_icon as Label
				if index < stars_earned:
					star_label.modulate = Color(1.0, 0.84, 0.0)
					star_label.text = "★"
				else:
					star_label.modulate = Color(0.3, 0.3, 0.3)
					star_label.text = "☆"

	var seed_value: int = maxi(0, int(float(_read_first_stat(stats, ["seed", "run_seed"], 0))))
	var round_value: int = maxi(1, int(float(_read_first_stat(stats, ["round", "depth", "current_round", "current_floor"], 1))))
	var best_depth: int = maxi(0, int(float(_read_first_stat(stats, ["best_depth", "best_run_depth"], 0))))
	var best_score: int = maxi(0, int(float(_read_first_stat(stats, ["best_score", "best_run_score"], 0))))
	var streak_value: int = maxi(0, int(float(_read_first_stat(stats, ["streak", "best_streak"], 0))))
	var puzzle_id: String = str(_read_first_stat(stats, ["puzzle_id", "id"], ""))
	var difficulty: String = str(_read_first_stat(stats, ["difficulty"], "endless")).capitalize()
	var share_code: String = str(_read_first_stat(stats, ["share_code", "share_token"], ""))

	if seed_stat_label:
		seed_stat_label.text = str(seed_value) if seed_value > 0 else "Tutorial"
	if best_stat_label:
		if best_depth > 0 or best_score > 0:
			best_stat_label.text = "Depth %d  •  %s pts" % [best_depth, _format_number_with_commas(best_score)]
		else:
			best_stat_label.text = "First clear"
	if subtitle_label:
		var subtitle: String = "%s  •  Round %d" % [difficulty, round_value]
		if puzzle_id.is_empty():
			subtitle += "  •  Fresh result"
		else:
			subtitle += "  •  " + puzzle_id
		subtitle_label.text = subtitle
	if context_label:
		var context_parts: Array[String] = []
		if streak_value > 0:
			context_parts.append("Streak %d" % streak_value)
		if not _read_first_stat(stats, ["is_daily"], false):
			context_parts.append("Offline-ready")
		else:
			context_parts.append("Daily challenge")
		context_label.text = "  •  ".join(context_parts)

	if radial_meter:
		var target_time: float = maxf(1.0, float(_read_first_stat(stats, ["par_time_seconds", "target_time_seconds"], 120.0)))
		var progress: float = clampf(1.0 - (total_seconds / target_time), 0.0, 1.0)
		radial_meter.value = progress * 100.0
		radial_meter.tint_progress = Color(0.2, 0.8, 0.4) if progress >= 0.66 else Color(0.95, 0.65, 0.15) if progress >= 0.33 else Color(0.8, 0.25, 0.2)

	set_share_code(share_code)
	_applied_result = {
		"level": level_name,
		"time_seconds": total_seconds,
		"score": score_value,
		"stars": stars_earned,
		"seed": seed_value,
		"round": round_value,
		"best_depth": best_depth,
		"best_score": best_score,
		"streak": streak_value,
		"puzzle_id": puzzle_id,
		"difficulty": difficulty.to_lower(),
		"share_code": _share_code,
		"context": result_context,
	}
	if confetti_particles:
		confetti_particles.emitting = not _is_reduced_motion_enabled()
	call_deferred("_apply_responsive_layout")


func _read_first_stat(stats: Variant, keys: Array, fallback: Variant) -> Variant:
	for key: Variant in keys:
		var value: Variant = _read_stat(stats, str(key), null)
		if value != null:
			return value
	return fallback


func _read_stat(stats: Variant, key: String, fallback: Variant) -> Variant:
	if stats is Dictionary:
		return (stats as Dictionary).get(key, fallback)
	if stats is Object:
		return (stats as Object).get(key)
	return fallback


func _is_reduced_motion_enabled() -> bool:
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("get_settings"):
		return false
	var settings: Dictionary = save_manager.call("get_settings")
	return bool(settings.get("reduced_motion", false))


func _on_next_pressed() -> void:
	if _next_transition_pending:
		return
	_next_transition_pending = true
	if next_button:
		next_button.disabled = true
	if is_endless_gauntlet:
		if not is_inside_tree():
			return
		# GridManager starts its reveal animation and the gauntlet advances on
		# the same signal. A short guard here prevents a double click from
		# scheduling two rounds before the child puzzle has been replaced.
		await get_tree().create_timer(0.2).timeout
		if not is_inside_tree():
			return
	start_next_nonogram_requested.emit()


func _on_leave_pressed() -> void:
	leave_requested.emit()


func _on_replay_pressed() -> void:
	if replay_button:
		replay_button.disabled = true
	replay_requested.emit()


func _on_new_run_pressed() -> void:
	if new_run_button:
		new_run_button.disabled = true
	new_run_requested.emit()


func _on_share_pressed() -> void:
	if _share_copy_in_progress:
		return
	var code_to_copy: String = _share_code
	if code_to_copy.is_empty():
		code_to_copy = "seed-%d" % int(_applied_result.get("seed", 0))
	_share_copy_in_progress = true
	var copied: bool = false
	# The native DisplayServer clipboard is a synchronous call, so a successful
	# return is a real copy. The web DisplayServer routes clipboard_set through
	# the same asynchronous, permission-gated navigator.clipboard API, so web
	# must never take this path: it is confirmed separately below or not at all.
	if not OS.has_feature("web") and DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(code_to_copy)
		copied = true
	var web_copy_started: bool = _begin_web_clipboard_copy(code_to_copy)
	share_requested.emit(code_to_copy)
	if copied:
		_set_share_status("Replay code copied", false)
	elif web_copy_started:
		# The browser has not answered yet. Say that instead of guessing.
		_set_share_status("Copying replay code…", false)
	else:
		_set_share_status(_manual_copy_instruction(code_to_copy), true)
	if share_button:
		share_button.set("disabled", false)
	_share_copy_in_progress = false


func _begin_web_clipboard_copy(text: String) -> bool:
	# Returns true only when a web copy was actually requested. The confirmed
	# result arrives later through _process, which refuses to report success
	# unless the browser resolved the write.
	_clear_web_copy_state()
	if not OS.has_feature("web") or not ClassDB.class_exists("JavaScriptBridge"):
		return false
	if not _web_clipboard_supported():
		return false
	_web_copy_code = text
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
	var code: String = _web_copy_code
	_clear_web_copy_state()
	if copied:
		_set_share_status("Replay code copied", false)
	else:
		_set_share_status(_manual_copy_instruction(code), true)


func _clear_web_copy_state() -> void:
	_web_copy_pending = false
	_web_copy_code = ""
	_web_copy_elapsed = 0.0
	_web_copy_poll_accumulator = 0.0
	set_process(false)


func _set_share_status(text: String, is_warning: bool) -> void:
	if share_status_label == null or not is_instance_valid(share_status_label):
		return
	share_status_label.text = text
	var status_color: Color = Color(0.75, 0.5, 0.1, 1.0) if is_warning else Color(0.25, 0.45, 0.3, 1.0)
	share_status_label.add_theme_color_override("font_color", status_color)


func _manual_copy_instruction(code: String) -> String:
	return "Copy this replay code: " + code


func _focus_primary_action() -> void:
	if not is_inside_tree():
		return
	if next_button and next_button.is_inside_tree() and not next_button.disabled:
		next_button.grab_focus()
	elif replay_button and replay_button.is_inside_tree() and not replay_button.disabled:
		replay_button.grab_focus()
	elif leave_button and leave_button.is_inside_tree():
		leave_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_leave_pressed()
		get_viewport().set_input_as_handled()


func _format_number_with_commas(number: int) -> String:
	var number_string: String = str(maxi(0, number))
	var modulo: int = number_string.length() % 3
	var result: String = ""
	for index in range(number_string.length()):
		if index != 0 and index % 3 == modulo:
			result += ","
		result += number_string[index]
	return result


func _apply_responsive_layout() -> void:
	if not is_inside_tree():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var insets: Vector4 = _get_safe_area_insets(viewport_size)
	var available_width: float = maxf(1.0, viewport_size.x - insets.x - insets.z)
	var available_height: float = maxf(1.0, viewport_size.y - insets.y - insets.w)
	var compact: bool = viewport_size.x < 520.0 or viewport_size.y < 620.0
	var very_short: bool = viewport_size.y < 600.0
	var card_width: float = minf(560.0, maxf(1.0, available_width - 24.0))
	var card_height: float = minf(760.0, maxf(1.0, available_height - 24.0))

	if card:
		card.anchor_left = 0.5
		card.anchor_right = 0.5
		card.anchor_top = 0.5
		card.anchor_bottom = 0.5
		card.offset_left = -card_width * 0.5
		card.offset_right = card_width * 0.5
		card.offset_top = -card_height * 0.5
		card.offset_bottom = card_height * 0.5
		card.clip_contents = false
	if card_content:
		card_content.add_theme_constant_override("separation", 3 if very_short else 7 if compact else 12)
	if meter_container:
		meter_container.visible = false
		meter_container.custom_minimum_size = Vector2.ZERO
	if illustration_container:
		illustration_container.visible = not very_short
		illustration_container.custom_minimum_size = Vector2(0.0, 64.0 if compact else 112.0)
	if subtitle_label:
		subtitle_label.visible = not very_short
		subtitle_label.add_theme_font_size_override("font_size", 14 if compact else 16)
	if context_label:
		context_label.visible = not very_short
		context_label.add_theme_font_size_override("font_size", 13 if compact else 15)
	if action_row:
		action_row.columns = 1 if available_width < 360.0 else 3
		action_row.add_theme_constant_override("h_separation", 6 if compact else 10)
		action_row.add_theme_constant_override("v_separation", 4)
	for secondary_button: Button in [replay_button, new_run_button, share_button]:
		if secondary_button:
			secondary_button.custom_minimum_size = Vector2(0.0, 44.0 if compact else 48.0)
			secondary_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			secondary_button.clip_text = true
			secondary_button.focus_mode = Control.FOCUS_ALL
	if share_status_label:
		share_status_label.visible = not very_short
		share_status_label.add_theme_font_size_override("font_size", 12 if compact else 14)
	if leave_button:
		leave_button.custom_minimum_size = Vector2(0.0, 48.0)
		leave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		leave_button.clip_text = true
		leave_button.focus_mode = Control.FOCUS_ALL
	if next_button:
		next_button.custom_minimum_size = Vector2(0.0, 48.0)
		next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		next_button.clip_text = true
		next_button.focus_mode = Control.FOCUS_ALL
	if confetti_particles:
		confetti_particles.position = Vector2(viewport_size.x * 0.5, -20.0)
		confetti_particles.emission_rect_extents = Vector2(maxf(1.0, viewport_size.x * 0.5), 1.0)


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
