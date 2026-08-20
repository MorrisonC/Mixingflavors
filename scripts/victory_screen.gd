extends Control

signal start_next_nonogram_requested

@onready var header_label: Label = $Background/PanelContainer/VBoxContainer/HeaderLabel
@onready var clock_label: Label = $Background/PanelContainer/VBoxContainer/ClockPanel/ClockLabel
@onready var stars_container: HBoxContainer = $Background/PanelContainer/VBoxContainer/IllustrationContainer/OverlayBox/VBoxContainer/StarsContainer
@onready var radial_meter: TextureProgressBar = $Background/PanelContainer/VBoxContainer/MeterContainer/TextureProgressBar
@onready var time_stat_label: Label = $Background/PanelContainer/VBoxContainer/StatsContainer/TimeRow/Value
@onready var score_stat_label: Label = $Background/PanelContainer/VBoxContainer/StatsContainer/ScoreRow/Value
@onready var stars_stat_label: Label = $Background/PanelContainer/VBoxContainer/StatsContainer/StarsRow/Value
@onready var next_button: Button = $Background/PanelContainer/VBoxContainer/NextButton
@onready var leave_button: Button = $Background/PanelContainer/VBoxContainer/LeaveButton
signal leave_requested
@onready var confetti_particles: CPUParticles2D = $ConfettiParticles

const NonogramStatsClass = preload("res://scripts/stats.gd")

func _ready() -> void:
	if leave_button:
		leave_button.pressed.connect(func(): emit_signal("leave_requested"))

	if next_button:
		next_button.pressed.connect(_on_next_pressed)
	# Initially hide the card if we want to animate it in later, but for now we just show it.

func initialize(stats) -> void: # Type is NonogramStatsClass implicitly to avoid circular/compile issues sometimes
	# 1. Level String
	if header_label:
		header_label.text = stats.current_level_string

	# 2. Format Time (MM:SS)
	var total_seconds = int(stats.time_seconds)
	var minutes = int(total_seconds / 60)
	var seconds = total_seconds % 60
	var time_string = "%02d:%02d" % [minutes, seconds]

	if clock_label:
		clock_label.text = time_string
	if time_stat_label:
		time_stat_label.text = time_string

	# 3. Format Score (Commas)
	var score_str = _format_number_with_commas(stats.raw_score)
	if score_stat_label:
		score_stat_label.text = score_str

	# 4. Stars Earned
	if stars_stat_label:
		stars_stat_label.text = str(stats.stars_earned) + "/3"

	# Update top star icons with AAA animated pop transitions
	if stars_container:
		for i in range(stars_container.get_child_count()):
			var star_icon = stars_container.get_child(i)
			if star_icon is Label:
				if i < stats.stars_earned:
					star_icon.modulate = Color(1.0, 0.84, 0.0) # Gold
					star_icon.text = "★"
					star_icon.pivot_offset = star_icon.size / 2
					star_icon.scale = Vector2.ZERO
					var delay = 0.2 + (float(i) * 0.15)
					var tween = create_tween()
					tween.tween_interval(delay)
					tween.tween_property(star_icon, "scale", Vector2(1.5, 1.5), 0.15).set_trans(Tween.TRANS_BACK)
					tween.tween_property(star_icon, "scale", Vector2(1.0, 1.0), 0.1)
				else:
					star_icon.modulate = Color(0.3, 0.3, 0.3) # Dark Gray
					star_icon.text = "☆"

	# Radial Meter
	if radial_meter:
		var target_time = 300.0 # Example par time (5 mins) for 100%
		var progress = min(1.0, float(total_seconds) / target_time)
		radial_meter.value = progress * 100
		# Color coding based on time
		if progress < 0.33:
			radial_meter.tint_progress = Color(0.2, 0.8, 0.4) # Green (fast)
		elif progress < 0.66:
			radial_meter.tint_progress = Color(0.8, 0.8, 0.2) # Yellow (medium)
		else:
			radial_meter.tint_progress = Color(0.8, 0.2, 0.2) # Red (slow)

	# Fire confetti
	if confetti_particles:
		confetti_particles.emitting = true

func _on_next_pressed() -> void:
	emit_signal("start_next_nonogram_requested")

# Helper to format numbers with commas (e.g., 12500 -> 12,500)
func _format_number_with_commas(number: int) -> String:
	var string = str(number)
	var mod = string.length() % 3
	var res = ""
	for i in range(0, string.length()):
		if i != 0 and i % 3 == mod:
			res += ","
		res += string[i]
	return res
