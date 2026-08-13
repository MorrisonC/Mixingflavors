extends Node3D

const GameManagerClass = preload("res://scripts/GameManager.gd")
const VoxelLogicScene = preload("res://scenes/VoxelLogic.tscn")

var current_round: int = 1
var max_rounds: int = 999999 # Endless mode essentially
var time_left: float = 60.0
var current_wave_type: String = "normal"
var score: int = 0
var round_max_time: float = 60.0
var max_mistakes: int = 3

var active_puzzle: Node3D = null

@onready var timer_label: Label = $CanvasLayer/UI/TimerLabel
@onready var round_label: Label = $CanvasLayer/UI/RoundLabel
@onready var quit_btn: Button = $CanvasLayer/UI/QuitButton
@onready var confirm_dialog: Panel = $CanvasLayer/UI/ConfirmDialog
@onready var yes_btn: Button = $CanvasLayer/UI/ConfirmDialog/VBoxContainer/HBoxContainer/YesButton
@onready var no_btn: Button = $CanvasLayer/UI/ConfirmDialog/VBoxContainer/HBoxContainer/NoButton

func _ready() -> void:
	_apply_theme()

	quit_btn.pressed.connect(func():
		confirm_dialog.show()
	)
	no_btn.pressed.connect(func():
		confirm_dialog.hide()
	)
	yes_btn.pressed.connect(func():
		get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.MAIN_MENU)
	)

	_start_round()

func _apply_theme() -> void:
	pass

func _process(delta: float) -> void:
	if time_left > 0:
		time_left -= delta
		timer_label.text = "Time: " + str(int(ceil(time_left))) + "s"
		if time_left <= 0:
			_fail_gauntlet()

func _start_round() -> void:
	if is_instance_valid(active_puzzle):
		active_puzzle.queue_free()

	active_puzzle = VoxelLogicScene.instantiate()

	# Determine wave modifier
	if current_round % 10 == 0:
		current_wave_type = "boss"
	elif current_round % 4 == 0:
		current_wave_type = "blitz"
	elif current_round % 5 == 0:
		current_wave_type = "fog"
	else:
		current_wave_type = "normal"

	var puzzle_data = get_next_puzzle_for_mode()
	active_puzzle.custom_puzzle_data = puzzle_data

	# Determine theme
	var theme_name = puzzle_data.get("theme", "")
	if theme_name == "" and "id" in puzzle_data:
		if puzzle_data["id"].begins_with("valentine"):
			theme_name = "valentine"

	if theme_name.to_lower() == "valentine" or GameManagerClass.is_valentine_theme():
		var bg_index = ((current_round - 1) % 8) + 1
		var bg_tex = load("res://assets/textures/valentine/bg" + str(bg_index) + ".jpg")
		if bg_tex:
			var env = get_node_or_null("WorldEnvironment")
			if env and env.environment and env.environment.sky and env.environment.sky.sky_material:
				env.environment.sky.sky_material.panorama = bg_tex
	else:
		# Restore default abstract background
		var bg_tex = load("res://assets/textures/abstract_bg.png")
		if bg_tex:
			var env = get_node_or_null("WorldEnvironment")
			if env and env.environment and env.environment.sky and env.environment.sky.sky_material:
				env.environment.sky.sky_material.panorama = bg_tex

	var round_text = "Round: " + str(current_round)
	if current_wave_type == "blitz": round_text += " [BLITZ!]"
	elif current_wave_type == "fog": round_text += " [FOG!]"
	elif current_wave_type == "boss": round_text += " [BOSS!]"
	round_label.text = round_text

	if "par_time_seconds" in puzzle_data:
		time_left = float(puzzle_data["par_time_seconds"])
	else:
		time_left = 120.0

	if current_wave_type == "blitz":
		time_left *= 0.5 # Blitz is half time!

	round_max_time = time_left

	var main_ui = get_node_or_null("/root/Main/CanvasLayer/UIContainer")
	if main_ui:
		var canvas = get_node_or_null("CanvasLayer")
		if canvas:
			remove_child(canvas)
			main_ui.add_child(canvas)

	add_child(active_puzzle)

	# Sync UI Health
	var current_health = max_mistakes
	if current_round > 1 and active_puzzle.has_method("set"):
		active_puzzle.set("player_hp", current_health)

	active_puzzle.puzzle_solved.connect(_on_puzzle_solved)
	active_puzzle.mistake_made.connect(_on_mistake_made)

func get_next_puzzle_for_mode() -> Dictionary:
	var mode = get_node("/root/GameManager").selected_difficulty_mode
	if mode == "endless":
		return _get_endless_scaling_puzzle()

	var pr = get_node("/root/PuzzleRegistry")
	if pr:
		var pool = pr.get_puzzles_for_gauntlet(mode)
		if pool.is_empty():
			pool = pr.get_all_puzzles()
		if not pool.is_empty():
			return pool.pick_random()
	return {}

func _get_endless_scaling_puzzle() -> Dictionary:
	var target_tier = "easy"

	# Dynamic difficulty scaling based on score/speed metrics
	if score > 5000:
		target_tier = "boss"
	elif score > 2500:
		target_tier = "hard"
	elif score > 1000:
		target_tier = "medium"

	var pr = get_node("/root/PuzzleRegistry")
	if pr:
		var pool = pr.get_puzzles_for_gauntlet(target_tier)
		if pool.is_empty():
			pool = pr.get_all_puzzles()
		if not pool.is_empty():
			return pool.pick_random()
	return {}

func _on_puzzle_solved() -> void:
	var time_spent = round_max_time - time_left
	var time_ratio = time_spent / round_max_time

	# Flow framework: reward speed with health to maintain challenge balance
	var bonus = 0
	if time_ratio <= 0.5:
		bonus = 2
	elif time_ratio <= 0.75:
		bonus = 1

	max_mistakes += bonus

	# Meta Progression Unlocks
	if current_round == 10:
		get_node("/root/GameManager").unlock_theme("Wood")
	elif current_round == 20:
		get_node("/root/GameManager").unlock_theme("Marble")
	elif current_round == 30:
		get_node("/root/GameManager").unlock_theme("Neon Sci-Fi")

	# Score calculation
	var round_score = 100
	if current_wave_type == "blitz": round_score *= 2
	if current_wave_type == "boss": round_score *= 5
	score += round_score + int(time_left) * 10
	print("[EscapeGauntlet] Current Score: ", score)

	if bonus > 0:
		print("[EscapeGauntlet] Fast solve! Time ratio: ", time_ratio, " Bonus Health: +", bonus, " Current Health: ", max_mistakes)

	current_round += 1
	_start_round()

func _on_mistake_made(total_mistakes: int) -> void:
	if total_mistakes >= max_mistakes:
		_fail_gauntlet()

func _fail_gauntlet() -> void:
	if not active_puzzle: return
	active_puzzle.is_puzzle_active = false
	
	# Show Game Over Label
	var label = Label.new()
	label.text = "GAUNTLET FAILED\nGAME OVER"
	label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_color_override("font_color", Color(0.9, 0.1, 0.1))
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.position.x -= 300
	label.position.y -= 100

	var ui = $CanvasLayer/UI if has_node("CanvasLayer/UI") else get_node_or_null("/root/Main/CanvasLayer/UIContainer/CanvasLayer/UI")
	if ui: ui.add_child(label)
	
	print("[EscapeGauntlet] Gauntlet Failed!")

	var retry_btn = Button.new()
	retry_btn.text = "Retry"
	retry_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	retry_btn.position.y += 100
	retry_btn.position.x -= 150
	retry_btn.custom_minimum_size = Vector2(100, 50)
	retry_btn.add_theme_font_size_override("font_size", 24)
	retry_btn.pressed.connect(func():
		get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.ESCAPE_GAUNTLET)
	)
	var ui = $CanvasLayer/UI if has_node("CanvasLayer/UI") else get_node_or_null("/root/Main/CanvasLayer/UIContainer/CanvasLayer/UI")
	if ui: ui.add_child(retry_btn)

	var leave_btn = Button.new()
	leave_btn.text = "Leave"
	leave_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	leave_btn.position.y += 100
	leave_btn.position.x += 50
	leave_btn.custom_minimum_size = Vector2(100, 50)
	leave_btn.add_theme_font_size_override("font_size", 24)
	leave_btn.pressed.connect(func():
		get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.MAIN_MENU)
	)
	var ui = $CanvasLayer/UI if has_node("CanvasLayer/UI") else get_node_or_null("/root/Main/CanvasLayer/UIContainer/CanvasLayer/UI")
	if ui: ui.add_child(leave_btn)


func _win_gauntlet() -> void:
	# Unused in endless mode, but kept for compatibility just in case
	var label = Label.new()
	label.text = "GAUNTLET CLEARED!"
	label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", Color(0.15, 0.95, 0.45))
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.position.x -= 400
	label.position.y -= 100

	var ui = $CanvasLayer/UI if has_node("CanvasLayer/UI") else get_node_or_null("/root/Main/CanvasLayer/UIContainer/CanvasLayer/UI")
	if ui: ui.add_child(label)
	
	print("[EscapeGauntlet] Gauntlet Won!")
	var retry_btn = Button.new()
	retry_btn.text = "Retry"
	retry_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	retry_btn.position.y += 100
	retry_btn.position.x -= 150
	retry_btn.custom_minimum_size = Vector2(100, 50)
	retry_btn.add_theme_font_size_override("font_size", 24)
	retry_btn.pressed.connect(func():
		get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.ESCAPE_GAUNTLET)
	)
	var ui = $CanvasLayer/UI if has_node("CanvasLayer/UI") else get_node_or_null("/root/Main/CanvasLayer/UIContainer/CanvasLayer/UI")
	if ui: ui.add_child(retry_btn)

	var leave_btn = Button.new()
	leave_btn.text = "Leave"
	leave_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	leave_btn.position.y += 100
	leave_btn.position.x += 50
	leave_btn.custom_minimum_size = Vector2(100, 50)
	leave_btn.add_theme_font_size_override("font_size", 24)
	leave_btn.pressed.connect(func():
		get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.MAIN_MENU)
	)
	var ui = $CanvasLayer/UI if has_node("CanvasLayer/UI") else get_node_or_null("/root/Main/CanvasLayer/UIContainer/CanvasLayer/UI")
	if ui: ui.add_child(leave_btn)

