extends Node3D

const GameManagerClass = preload("res://scripts/GameManager.gd")
const Picross3DScene = preload("res://scenes/Picross3D.tscn")

var current_round: int = 1
var max_rounds: int = 3 # Round 3 is the Boss
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

	active_puzzle = Picross3DScene.instantiate()

	# Modify grid size based on round for difficulty BEFORE adding to tree
	if current_round == max_rounds:
		# Boss round
		round_label.text = "BOSS FIGHT"
		active_puzzle.grid_size = Vector3i(5, 5, 5) # Larger unique shape
		time_left = 120.0 # More time for boss
	else:
		round_label.text = "Round: " + str(current_round)
		active_puzzle.grid_size = Vector3i(2 + current_round, 2 + current_round, 2 + current_round)
		time_left = 60.0 # Reset timer per round

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
	print("[EscapeGauntlet] Gauntlet Failed!")
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.LONE_WOLF_NARRATIVE)

func _win_gauntlet() -> void:
	print("[EscapeGauntlet] Gauntlet Won!")
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.LONE_WOLF_NARRATIVE)
