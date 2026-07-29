extends Node3D

@onready var grid_manager: Node3D = $GridManager
@onready var mobile_touch_controls: Control = $UI/MobileTouchControls
@onready var save_button: Button = $UI/SaveButton
@onready var back_button: Button = $UI/BackButton
@onready var status_label: Label = $UI/StatusLabel

const GameManagerClass = preload("res://scripts/GameManager.gd")

func _ready() -> void:
	save_button.pressed.connect(_on_save_pressed)
	back_button.pressed.connect(_on_back_pressed)

	if grid_manager and grid_manager.has_method("build_grid"):
		# Build a default blank grid for editing
		grid_manager.grid_size = Vector3i(5, 5, 5)
		grid_manager.build_grid()

func _on_save_pressed() -> void:
	if not grid_manager:
		return

	var blocks_state = []
	for z in range(grid_manager.grid_size.z):
		for y in range(grid_manager.grid_size.y):
			for x in range(grid_manager.grid_size.x):
				var pos = Vector3i(x, y, z)
				var block = grid_manager.get_block_at(pos)
				if block and block.current_state != block.BlockState.DESTROYED:
					blocks_state.append({"x": x, "y": y, "z": z})

	var file = FileAccess.open("user://custom_puzzle.json", FileAccess.WRITE)
	if file:
		var json_str = JSON.stringify({"blocks": blocks_state, "size": {"x": grid_manager.grid_size.x, "y": grid_manager.grid_size.y, "z": grid_manager.grid_size.z}})
		file.store_string(json_str)
		file.close()
		status_label.text = "Puzzle Saved!"
	else:
		status_label.text = "Failed to save."

func _on_back_pressed() -> void:
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.MAIN_MENU)
