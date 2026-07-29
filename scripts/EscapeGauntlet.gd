extends Node3D

const GameManagerClass = preload("res://scripts/GameManager.gd")
const VoxelLogicScene = preload("res://scenes/VoxelLogic.tscn")

var current_round: int = 1
var max_rounds: int = 5 # 5 Valentine themed puzzles
var time_left: float = 60.0
var max_mistakes: int = 3

var active_puzzle: Node3D = null

@onready var timer_label: Label = $UI/TimerLabel
@onready var round_label: Label = $UI/RoundLabel

func _ready() -> void:
	_start_round()

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

	# Modify grid size based on round for difficulty BEFORE adding to tree
	if current_round == max_rounds:
		# Boss round
		round_label.text = "BOSS FIGHT"
		active_puzzle.grid_size = Vector3i(5, 5, 5) # Large Bow & Arrow shape
		time_left = 120.0 # More time for boss
	elif current_round in [1, 2]:
		round_label.text = "Round: " + str(current_round)
		active_puzzle.grid_size = Vector3i(3, 3, 3) # Heart, Love Letter
		time_left = 60.0
	else:
		round_label.text = "Round: " + str(current_round)
		active_puzzle.grid_size = Vector3i(4, 4, 4) # Diamond Ring, Rose
		time_left = 80.0

	add_child(active_puzzle)

	active_puzzle.puzzle_solved.connect(_on_puzzle_solved)
	active_puzzle.mistake_made.connect(_on_mistake_made)

func _on_puzzle_solved() -> void:
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
	$UI.add_child(label)
	
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
	$UI.add_child(label)
	
	print("[EscapeGauntlet] Gauntlet Won!")
	await get_tree().create_timer(5.0).timeout
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.MAIN_MENU)


