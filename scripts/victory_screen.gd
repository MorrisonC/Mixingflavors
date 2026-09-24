extends Control

signal start_next_nonogram_requested
signal leave_requested

@onready var header_label: Label = $Background/PanelContainer/VBoxContainer/HeaderLabel
@onready var clock_label: Label = $Background/PanelContainer/VBoxContainer/ClockPanel/ClockLabel
@onready var stars_container: HBoxContainer = $Background/PanelContainer/VBoxContainer/IllustrationContainer/OverlayBox/VBoxContainer/StarsContainer
@onready var radial_meter: TextureProgressBar = $Background/PanelContainer/VBoxContainer/MeterContainer/TextureProgressBar
@onready var time_stat_label: Label = $Background/PanelContainer/VBoxContainer/StatsContainer/TimeRow/Value
@onready var score_stat_label: Label = $Background/PanelContainer/VBoxContainer/StatsContainer/ScoreRow/Value
@onready var stars_stat_label: Label = $Background/PanelContainer/VBoxContainer/StatsContainer/StarsRow/Value
@onready var next_button: Button = $Background/PanelContainer/VBoxContainer/NextButton
@onready var leave_button: Button = $Background/PanelContainer/VBoxContainer/LeaveButton
@onready var confetti_particles: CPUParticles2D = $ConfettiParticles
@onready var card: PanelContainer = $Background/PanelContainer
@onready var card_content: VBoxContainer = $Background/PanelContainer/VBoxContainer
@onready var meter_container: Control = $Background/PanelContainer/VBoxContainer/MeterContainer
@onready var illustration_container: Control = $Background/PanelContainer/VBoxContainer/IllustrationContainer

var is_endless_gauntlet: bool = false
var _next_transition_pending: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if leave_button:
		leave_button.pressed.connect(_on_leave_pressed)
	if next_button:
		next_button.pressed.connect(_on_next_pressed)
	_detect_endless_context()
	resized.connect(_apply_responsive_layout)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")
	call_deferred("_focus_primary_action")


func _detect_endless_context() -> void:
	var candidate: Node = get_parent()
	while candidate != null:
		if candidate.name == "EscapeGauntlet" or candidate.has_method("get_next_puzzle_for_mode"):
			is_endless_gauntlet = true
			break
		candidate = candidate.get_parent()
	if is_endless_gauntlet and next_button:
		next_button.text = "Continue Gauntlet"
		next_button.tooltip_text = "Continue to the next endless round"


func initialize(stats: Variant) -> void:
	var level_name: String = str(_read_stat(stats, "current_level_string", "Level"))
	if header_label:
		header_label.text = level_name

	var total_seconds: int = int(float(_read_stat(stats, "time_seconds", 0.0)))
	var minutes: int = int(total_seconds / 60)
	var seconds: int = total_seconds % 60
	var time_string: String = "%02d:%02d" % [minutes, seconds]
	if clock_label:
		clock_label.text = time_string
	if time_stat_label:
		time_stat_label.text = time_string

	var score_value: int = int(float(_read_stat(stats, "raw_score", 0)))
	if score_stat_label:
		score_stat_label.text = _format_number_with_commas(score_value)

	var stars_earned: int = int(float(_read_stat(stats, "stars_earned", 0)))
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

	if radial_meter:
		var target_time: float = 300.0
		var progress: float = minf(1.0, float(total_seconds) / target_time)
		radial_meter.value = progress * 100.0
		if progress < 0.33:
			radial_meter.tint_progress = Color(0.2, 0.8, 0.4)
		elif progress < 0.66:
			radial_meter.tint_progress = Color(0.8, 0.8, 0.2)
		else:
			radial_meter.tint_progress = Color(0.8, 0.2, 0.2)

	if confetti_particles:
		confetti_particles.emitting = true
	call_deferred("_apply_responsive_layout")


func _read_stat(stats: Variant, key: String, fallback: Variant) -> Variant:
	if stats is Dictionary:
		return (stats as Dictionary).get(key, fallback)
	if stats is Object:
		return (stats as Object).get(key)
	return fallback


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_leave_pressed()
		get_viewport().set_input_as_handled()


func _focus_primary_action() -> void:
	if next_button and not next_button.disabled:
		next_button.grab_focus()
	elif leave_button:
		leave_button.grab_focus()


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
		card.clip_contents = true
	if card_content:
		card_content.add_theme_constant_override("separation", 4 if very_short else 8 if compact else 14)
	if meter_container:
		meter_container.visible = not very_short
		meter_container.custom_minimum_size = Vector2(clampf(card_width * 0.35, 80.0, 150.0), clampf(card_height * 0.2, 80.0, 150.0))
	if illustration_container:
		illustration_container.custom_minimum_size = Vector2(0.0, clampf(card_height * 0.25, 64.0, 180.0))
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
