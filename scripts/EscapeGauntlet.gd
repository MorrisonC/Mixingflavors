extends Node3D

const GameManagerClass = preload("res://scripts/GameManager.gd")
const VoxelLogicScene = preload("res://scenes/VoxelLogic.tscn")

var current_round: int = 1
var max_rounds: int = 999999 # Endless mode essentially
var time_left: float = 60.0
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
	var pr = get_node("/root/PuzzleRegistry")
	if pr and pr.manifest_data:
		var themes = pr.manifest_data.keys()
		if themes.size() > 0:
			var rand_theme = themes[randi() % themes.size()]
			# Add visual background/music randomized here based on theme
			# (In a full implementation, you'd load theme-specific assets here)
			pass

	if is_instance_valid(active_puzzle):
		active_puzzle.queue_free()

	active_puzzle = VoxelLogicScene.instantiate()

	var puzzle_data = get_next_puzzle_for_mode()
	active_puzzle.custom_puzzle_data = puzzle_data

	round_label.text = "Round: " + str(current_round)

	if "par_time_seconds" in puzzle_data:
		time_left = float(puzzle_data["par_time_seconds"])
		round_max_time = time_left
	else:
		time_left = 120.0
		round_max_time = 120.0

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
	if current_round >= 18:
		target_tier = "boss"
	elif current_round >= 12:
		target_tier = "hard"
	elif current_round >= 6:
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
	$CanvasLayer/UI.add_child(label)
	
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
	$CanvasLayer/UI.add_child(retry_btn)

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
	$CanvasLayer/UI.add_child(leave_btn)


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
	$CanvasLayer/UI.add_child(label)
	
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
	$CanvasLayer/UI.add_child(retry_btn)

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
	$CanvasLayer/UI.add_child(leave_btn)

