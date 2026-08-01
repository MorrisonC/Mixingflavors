extends Node3D

const GameManagerClass = preload("res://scripts/GameManager.gd")
const VoxelLogicScene = preload("res://scenes/VoxelLogic.tscn")

var current_round: int = 1
var max_rounds: int = 5 # 5 Valentine themed puzzles
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
	if GameManagerClass.is_valentine_theme():
		var env = $WorldEnvironment.environment
		if env:
						pass

		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.98, 0.92, 0.93, 1)
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		confirm_dialog.add_theme_stylebox_override("panel", style)

		var label = $CanvasLayer/UI/ConfirmDialog/VBoxContainer/Label
		label.add_theme_color_override("font_color", Color(0.85, 0.15, 0.3, 1))

		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.95, 0.45, 0.55, 1)
		btn_style.corner_radius_top_left = 8
		btn_style.corner_radius_top_right = 8
		btn_style.corner_radius_bottom_left = 8
		btn_style.corner_radius_bottom_right = 8

		for btn in [quit_btn, yes_btn, no_btn]:
			btn.add_theme_stylebox_override("normal", btn_style)

func _process(delta: float) -> void:
	if time_left > 0:
		time_left -= delta
		timer_label.text = "Time: " + str(int(ceil(time_left))) + "s"
		if time_left <= 0:
			_fail_gauntlet()

func _start_round() -> void:

	var bg_index = ((current_round - 1) % 5) + 1
	var bg_tex = load("res://assets/textures/valentine/bg" + str(bg_index) + ".jpg")
	if bg_tex:
		var env = $WorldEnvironment.environment
		if env and env.sky and env.sky.sky_material:
			env.sky.sky_material.panorama = bg_tex

	if is_instance_valid(active_puzzle):
		active_puzzle.queue_free()

	active_puzzle = VoxelLogicScene.instantiate()

	var puzzle_data = get_next_puzzle_for_mode()
	active_puzzle.custom_puzzle_data = puzzle_data

	if current_round == max_rounds and get_node("/root/GameManager").selected_difficulty_mode != "endless":
		round_label.text = "BOSS FIGHT"
	else:
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

	var pool = PuzzleRegistry.get_puzzles_by_tier(mode)
	if pool.is_empty():
		pool = PuzzleRegistry.get_all_puzzles()
	return pool.pick_random()

func _get_endless_scaling_puzzle() -> Dictionary:
	var target_tier = "easy"
	if current_round >= 12:
		target_tier = "hard"
	elif current_round >= 6:
		target_tier = "medium"

	var pool = PuzzleRegistry.get_puzzles_by_tier(target_tier)
	if pool.is_empty():
		pool = PuzzleRegistry.get_all_puzzles()
	return pool.pick_random()


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

	if current_round >= max_rounds:

		_win_gauntlet()
	else:
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
	await get_tree().create_timer(3.0).timeout
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.MAIN_MENU)

func _win_gauntlet() -> void:
	# Show Victory Label
	var label = Label.new()
	label.text = "VALENTINE GAUNTLET CLEARED!\nYOU UNLOCKED THE MYSTERY OF LOVE ❤️"
	label.horizontal_alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", Color(0.95, 0.15, 0.45))
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.position.x -= 400
	label.position.y -= 100
	$CanvasLayer/UI.add_child(label)
	
	print("[EscapeGauntlet] Gauntlet Won!")
	await get_tree().create_timer(5.0).timeout
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.MAIN_MENU)


