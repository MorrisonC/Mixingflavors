extends Node3D

class_name GridManager

const VoxelLogicSolver = preload("res://scripts/VoxelLogicSolver.gd")

@export var grid_size: Vector3i = Vector3i(5, 5, 5)
@export var block_scene: PackedScene = preload("res://scenes/Block.tscn")
@export var camera: Camera3D

# Internal storage
var blocks: Dictionary = {}
var target_solution: Dictionary = {}

var target_shape: Array[Vector3i] = []
var voxel_states: Dictionary = {}

var slice_max: Vector3i
var move_history: Array = []
var is_player_action: bool = true

@onready var labels_container: Node3D = get_node_or_null("LabelsContainer")

signal puzzle_solved
signal mistake_made(total_mistakes)
signal combo_updated(current_combo)
signal history_updated(can_undo)
signal game_over
signal floor_cleared
signal block_destroyed(grid_pos: Vector3i, is_player_action: bool)
signal voxel_marked(grid_pos: Vector3i)

var mistakes: int = 0
var combo: int = 0
var player_hp: int = 3
var boss_hp: float = 100.0
var max_boss_hp: float = 100.0
var current_floor: int = 1
var custom_puzzle_data: Dictionary = {}

var start_time: float = 0.0
var time_elapsed: float = 0.0
var is_puzzle_active: bool = true
var base_grid_size: int = 3

# UI Elements
@onready var slice_slider_x: HSlider = null
@onready var slice_slider_y: HSlider = null
@onready var slice_slider_z: HSlider = null
@onready var slice_controls: VBoxContainer = null
@onready var chisel_btn: Button = null
@onready var mark_btn: Button = null
@onready var rotate_btn: Button = null
@onready var slice_toggle_btn: Button = null
@onready var undo_btn: Button = null
@onready var export_btn: Button = null

@onready var round_label: Label = null
@onready var hp_label: Label = null
@onready var combo_label: Label = null
@onready var timer_label: Label = null
@onready var boss_name_label: Label = null
@onready var boss_hp_bar: ProgressBar = null

enum EditMode { DESTROY, MARK, ROTATE, BUILD, PAINT }
var current_mode: EditMode = EditMode.DESTROY
var is_editor_mode: bool = false
enum HintType { SIMPLE, CIRCLE, SQUARE }
var hovered_block: VoxelBlock = null

const GameManagerClass = preload("res://scripts/GameManager.gd")

var has_custom_puzzle: bool = false
var is_tutorial: bool = false
var tutorial_manager: TutorialManager = null
var tutorial_ui: CanvasLayer = null

func _ready() -> void:
	if is_instance_valid(GameManager) and GameManager.has_method("is_valentine_theme") and GameManager.is_valentine_theme():
		var env_node = get_node_or_null("WorldEnvironment")
		if env_node and env_node.environment:
			pass

	var game_manager = get_node_or_null("/root/GameManager")
	# custom_puzzle_data handled at class level

	if game_manager and game_manager.get("mode_payload"):
		if game_manager.mode_payload.get("mode") == "editor":
			is_editor_mode = true
		if game_manager.mode_payload.has("custom_puzzle"):
			has_custom_puzzle = true
			custom_puzzle_data = game_manager.mode_payload["custom_puzzle"]

	# Find UI elements
	slice_controls = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/SliceControls")
	if slice_controls:
		slice_slider_x = slice_controls.get_node_or_null("SliderX")
		slice_slider_y = slice_controls.get_node_or_null("SliderY")
		slice_slider_z = slice_controls.get_node_or_null("SliderZ")

	chisel_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/ChiselButton")
	var paint_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/PaintButton")
	mark_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/MarkButton")
	rotate_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/RotateButton")
	slice_toggle_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/SliceToggleButton")
	undo_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/UndoButton")
	export_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/ExportButton")

	if is_editor_mode and mark_btn and chisel_btn and export_btn:
		chisel_btn.text = "Remove"
		mark_btn.text = "Add"
		mark_btn.modulate = Color(0.2, 1.0, 0.2)
		export_btn.visible = true

	var top_info = get_node_or_null("CanvasLayer/Control/MarginContainer/TopInfoBar/HBoxContainer")
	if top_info:
		round_label = top_info.get_node_or_null("RoundLabel")
		hp_label = top_info.get_node_or_null("HPLabel")
		combo_label = top_info.get_node_or_null("ComboLabel")
		timer_label = top_info.get_node_or_null("TimerLabel")
		var leave_btn = top_info.get_node_or_null("LeaveButton")
		if leave_btn and not leave_btn.pressed.is_connected(_on_leave_requested):
			leave_btn.pressed.connect(_on_leave_requested)

		var boss_container = top_info.get_node_or_null("BossContainer")
		if boss_container:
			boss_name_label = boss_container.get_node_or_null("BossNameLabel")
			boss_hp_bar = boss_container.get_node_or_null("BossHPBar")

	start_level()

	var touch_controls = get_node_or_null("CanvasLayer/Control")
	if touch_controls and touch_controls is MobileTouchControls:
		if not touch_controls.chisel_voxel_requested.is_connected(on_chisel_requested):
			touch_controls.chisel_voxel_requested.connect(on_chisel_requested)
		if not touch_controls.mark_voxel_requested.is_connected(on_mark_requested):
			touch_controls.mark_voxel_requested.connect(on_mark_requested)
		if not touch_controls.hover_voxel_requested.is_connected(on_hover_requested):
			touch_controls.hover_voxel_requested.connect(on_hover_requested)

	# Connect UI
	if slice_slider_x and not slice_slider_x.value_changed.is_connected(_on_slice_x_changed):
		slice_slider_x.max_value = grid_size.x - 1
		slice_slider_x.value = grid_size.x - 1
		slice_slider_x.value_changed.connect(_on_slice_x_changed)
	if slice_slider_y and not slice_slider_y.value_changed.is_connected(_on_slice_y_changed):
		slice_slider_y.max_value = grid_size.y - 1
		slice_slider_y.value = grid_size.y - 1
		slice_slider_y.value_changed.connect(_on_slice_y_changed)
	if slice_slider_z and not slice_slider_z.value_changed.is_connected(_on_slice_z_changed):
		slice_slider_z.max_value = grid_size.z - 1
		slice_slider_z.value = grid_size.z - 1
		slice_slider_z.value_changed.connect(_on_slice_z_changed)

	if chisel_btn and not chisel_btn.pressed.is_connected(_on_chisel_mode_selected):
		chisel_btn.pressed.connect(_on_chisel_mode_selected)
	if paint_btn and not paint_btn.pressed.is_connected(_on_paint_mode_selected):
		paint_btn.pressed.connect(_on_paint_mode_selected)
	if mark_btn and not mark_btn.pressed.is_connected(_on_mark_mode_selected):
		mark_btn.pressed.connect(_on_mark_mode_selected)
	if rotate_btn and not rotate_btn.pressed.is_connected(_on_rotate_mode_selected):
		rotate_btn.pressed.connect(_on_rotate_mode_selected)
	if slice_toggle_btn and not slice_toggle_btn.pressed.is_connected(_on_slice_toggle_pressed):
		slice_toggle_btn.pressed.connect(_on_slice_toggle_pressed)
	if undo_btn and not undo_btn.pressed.is_connected(undo_last_move):
		undo_btn.pressed.connect(undo_last_move)
	if export_btn and not export_btn.pressed.is_connected(_export_puzzle):
		export_btn.pressed.connect(_export_puzzle)

	if has_custom_puzzle:
		_load_custom_puzzle(custom_puzzle_data)

func _load_custom_puzzle(puzzle_data: Dictionary) -> void:
	if puzzle_data.get("theme") == "tutorial" or puzzle_data.get("id") == "tutorial_star":
		is_tutorial = true

		# Instantiate tutorial manager and UI
		tutorial_manager = TutorialManager.new()
		tutorial_manager.grid_manager = self
		add_child(tutorial_manager)

		var tutorial_ui_scene = load("res://scenes/TutorialUI.tscn")
		if tutorial_ui_scene:
			tutorial_ui = tutorial_ui_scene.instantiate()
			add_child(tutorial_ui)
			tutorial_ui.setup(tutorial_manager)

			# Connect signals for tutorial
			var touch_controls = get_node_or_null("CanvasLayer/Control")
			if touch_controls and touch_controls is MobileTouchControls:
				if touch_controls.has_signal("camera_rotated"):
					touch_controls.camera_rotated.connect(tutorial_manager.on_camera_rotated)
				if slice_slider_y:
					slice_slider_y.value_changed.connect(func(val): tutorial_manager.on_layer_slider_changed("Y", val))

			if self.has_signal("block_destroyed"):
				self.block_destroyed.connect(func(pos, is_player): tutorial_manager.on_voxel_chiseled(pos, true))
			if self.has_signal("voxel_marked"):
				self.voxel_marked.connect(tutorial_manager.on_voxel_marked)
			if self.has_signal("puzzle_solved"):
				self.puzzle_solved.connect(tutorial_manager.on_puzzle_solved)

	grid_size = Vector3i(puzzle_data["dims"][0], puzzle_data["dims"][1], puzzle_data["dims"][2])
	slice_max = grid_size

	target_solution.clear()
	for pos in blocks.keys():
		blocks[pos].queue_free()
	blocks.clear()
	move_history.clear()

	_build_grid()

	if puzzle_data.has("hints"):
		target_solution = VoxelLogicSolver.solve(grid_size, puzzle_data["hints"])
	elif puzzle_data.has("target_voxels"):
		for z in range(grid_size.z):
			for y in range(grid_size.y):
				for x in range(grid_size.x):
					target_solution[Vector3i(x, y, z)] = false
		for v in puzzle_data["target_voxels"]:
			target_solution[Vector3i(v[0], v[1], v[2])] = true
	elif puzzle_data.has("cells"):
		var cells = puzzle_data["cells"]
		var index = 0
		for z in range(grid_size.z):
			for y in range(grid_size.y):
				for x in range(grid_size.x):
					var pos = Vector3i(x, y, z)
					if index < cells.size() and cells[index] == 1:
						target_solution[pos] = true
					else:
						target_solution[pos] = false
					index += 1

	target_shape.clear()
	voxel_states.clear()
	for pos in target_solution.keys():
		var is_target = target_solution[pos]
		if is_target:
			target_shape.append(pos)
		voxel_states[pos] = {
			"is_target": is_target,
			"is_chiseled": false,
			"is_marked": false
		}

	_update_clues()


func start_level() -> void:
	is_puzzle_active = true
	start_time = Time.get_ticks_msec()
	mistakes = 0
	combo = 0
	player_hp = 3
	move_history.clear()

	# Clear old blocks
	for pos in blocks.keys():
		blocks[pos].queue_free()
	blocks.clear()
	target_solution.clear()

	grid_size = Vector3i(base_grid_size, base_grid_size, base_grid_size)
	slice_max = grid_size - Vector3i(1, 1, 1)

	max_boss_hp = 100.0 + (current_floor * 50.0)
	boss_hp = max_boss_hp

	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.get("mode_payload") and game_manager.mode_payload.has("custom_puzzle"):
		_load_custom_puzzle(game_manager.mode_payload["custom_puzzle"])
		return

	_generate_solution()
	_build_grid()

	target_shape.clear()
	voxel_states.clear()
	for pos in target_solution.keys():
		var is_target = target_solution[pos]
		if is_target:
			target_shape.append(pos)
		voxel_states[pos] = {
			"is_target": is_target,
			"is_chiseled": false,
			"is_marked": false
		}

	_update_slicing()

	_update_clues()

	# Dynamically set max_zoom based on grid size and adjust camera
	if camera:
		var max_dim = max(grid_size.x, max(grid_size.y, grid_size.z))
		var target_zoom = float(max_dim) * 2.5
		var pivot = camera.get_parent()
		while pivot != null and not pivot is CameraPivotController and not "max_zoom" in pivot:
			pivot = pivot.get_parent()

		if pivot and "max_zoom" in pivot:
			pivot.max_zoom = target_zoom * 2.0
			pivot.min_zoom = target_zoom * 0.5
		elif pivot and "max_distance" in pivot:
			pivot.max_distance = target_zoom * 2.0
			pivot.min_distance = target_zoom * 0.5

		if pivot and "target_distance" in pivot:
			pivot.target_distance = target_zoom
		else:
			camera.position.z = target_zoom

	# Find UI elements
	slice_controls = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/SliceControls")
	if slice_controls:
		slice_slider_x = slice_controls.get_node_or_null("SliderX")
		slice_slider_y = slice_controls.get_node_or_null("SliderY")
		slice_slider_z = slice_controls.get_node_or_null("SliderZ")

	chisel_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/ChiselButton")
	mark_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/MarkButton")
	rotate_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/RotateButton")
	slice_toggle_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/SliceToggleButton")
	undo_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/UndoButton")
	export_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/ExportButton")

	var top_info = get_node_or_null("CanvasLayer/Control/MarginContainer/TopInfoBar/HBoxContainer")
	if top_info:
		round_label = top_info.get_node_or_null("RoundLabel")
		hp_label = top_info.get_node_or_null("HPLabel")
		combo_label = top_info.get_node_or_null("ComboLabel")
		timer_label = top_info.get_node_or_null("TimerLabel")
		var leave_btn = top_info.get_node_or_null("LeaveButton")
		if leave_btn and not leave_btn.pressed.is_connected(_on_leave_requested):
			leave_btn.pressed.connect(_on_leave_requested)

		var boss_container = top_info.get_node_or_null("BossContainer")
		if boss_container:
			boss_name_label = boss_container.get_node_or_null("BossNameLabel")
			boss_hp_bar = boss_container.get_node_or_null("BossHPBar")

	# Connect UI

	if slice_slider_x:
		slice_slider_x.max_value = grid_size.x - 1
		slice_slider_x.value = grid_size.x - 1
		slice_slider_x.value_changed.connect(_on_slice_x_changed)
	if slice_slider_y:
		slice_slider_y.max_value = grid_size.y - 1
		slice_slider_y.value = grid_size.y - 1
		slice_slider_y.value_changed.connect(_on_slice_y_changed)
	if slice_slider_z:
		slice_slider_z.max_value = grid_size.z - 1
		slice_slider_z.value = grid_size.z - 1
		slice_slider_z.value_changed.connect(_on_slice_z_changed)

	if chisel_btn:
		chisel_btn.pressed.connect(_on_chisel_mode_selected)
	if mark_btn:
		mark_btn.pressed.connect(_on_mark_mode_selected)
	if rotate_btn:
		rotate_btn.pressed.connect(_on_rotate_mode_selected)
	if slice_toggle_btn:
		slice_toggle_btn.pressed.connect(_on_slice_toggle_pressed)
	if undo_btn:
		undo_btn.pressed.connect(undo_last_move)

	_update_ui_state()

	# Dynamically set max_zoom based on grid size and adjust camera
	if camera:
		var max_dim = max(grid_size.x, max(grid_size.y, grid_size.z))
		var target_zoom = float(max_dim) * 2.5
		var pivot = camera.get_parent()
		while pivot != null and not pivot is CameraPivotController and not "max_zoom" in pivot:
			pivot = pivot.get_parent()

		if pivot and "max_zoom" in pivot:
			pivot.max_zoom = target_zoom * 2.0
			pivot.min_zoom = target_zoom * 0.5
		elif pivot and "max_distance" in pivot:
			pivot.max_distance = target_zoom * 2.0
			pivot.min_distance = target_zoom * 0.5

		if pivot and "target_distance" in pivot:
			pivot.target_distance = target_zoom
		else:
			camera.position.z = target_zoom

func _process(delta: float) -> void:
	if is_puzzle_active:
		time_elapsed = (Time.get_ticks_msec() - start_time) / 1000.0
		if timer_label:
			timer_label.text = "Time: %.1f" % time_elapsed

func _update_ui_state() -> void:
	if hp_label:
		var gauntlet = get_parent()
		var max_hp = 3
		if gauntlet and "max_mistakes" in gauntlet:
			max_hp = gauntlet.max_mistakes
		hp_label.text = "HP: %d/%d" % [player_hp, max_hp]

	if round_label:
		round_label.text = "Floor %d" % current_floor
	if boss_hp_bar:
		boss_hp_bar.max_value = max_boss_hp
		boss_hp_bar.value = boss_hp
	if boss_name_label:
		boss_name_label.text = "Maze Guardian F%d" % current_floor
	if combo_label:
		combo_label.text = "Combo: x%d" % combo

	if chisel_btn and mark_btn and rotate_btn:
		chisel_btn.disabled = (current_mode == EditMode.DESTROY)
		mark_btn.disabled = (current_mode == EditMode.MARK or current_mode == EditMode.BUILD)
		rotate_btn.disabled = (current_mode == EditMode.ROTATE)

func _on_chisel_mode_selected() -> void:
	current_mode = EditMode.DESTROY
	_update_ui_state()
	var touch_controls = get_node_or_null("CanvasLayer/Control")
	if touch_controls and touch_controls is MobileTouchControls:
		touch_controls.set_touch_mode(touch_controls.TouchMode.CHISEL)

func _on_paint_mode_selected() -> void:
	current_mode = EditMode.PAINT if not is_editor_mode else EditMode.BUILD
	_update_ui_state()
	var touch_controls = get_node_or_null("CanvasLayer/Control")
	if touch_controls and touch_controls is MobileTouchControls:
		touch_controls.set_touch_mode(touch_controls.TouchMode.PAINT)

func _on_mark_mode_selected() -> void:
	if is_editor_mode:
		current_mode = EditMode.BUILD
	else:
		current_mode = EditMode.MARK
	_update_ui_state()
	var touch_controls = get_node_or_null("CanvasLayer/Control")
	if touch_controls and touch_controls is MobileTouchControls:
		touch_controls.set_touch_mode(touch_controls.TouchMode.MARK)

func _on_rotate_mode_selected() -> void:
	current_mode = EditMode.ROTATE
	_update_ui_state()
	var touch_controls = get_node_or_null("CanvasLayer/Control")
	if touch_controls and touch_controls is MobileTouchControls:
		touch_controls.set_touch_mode(touch_controls.TouchMode.ROTATE)

func _on_slice_toggle_pressed() -> void:
	if slice_controls:
		slice_controls.visible = not slice_controls.visible

func _generate_solution() -> void:
	target_solution.clear()
	
	# Detect round from EscapeGauntlet if active
	var round_num = 1
	var gauntlet = get_parent()
	if gauntlet and gauntlet.name == "EscapeGauntlet" and "current_round" in gauntlet:
		round_num = gauntlet.current_round

	if grid_size == Vector3i(3, 3, 3):
		if round_num == 1:
			# Heart Shape for Round 1
			var heart_pattern = [
				# z=0
				[0,0,0], [1,0,1], [0,1,0],
				# z=1
				[1,0,1], [1,1,1], [0,1,0],
				# z=2
				[0,0,0], [0,1,0], [0,0,0]
			]
			for z in range(3):
				for y in range(3):
					for x in range(3):
						target_solution[Vector3i(x, y, z)] = (heart_pattern[z * 3 + y][x] == 1)
		else:
			# Love Letter / Envelope Shape for Round 2
			var letter_pattern = [
				# z=0
				[1,1,1], [1,1,1], [1,1,1],
				# z=1
				[1,0,1], [1,1,1], [1,1,1],
				# z=2
				[0,0,0], [1,0,1], [1,1,1]
			]
			for z in range(3):
				for y in range(3):
					for x in range(3):
						target_solution[Vector3i(x, y, z)] = (letter_pattern[z * 3 + y][x] == 1)
	elif grid_size == Vector3i(4, 4, 4):
		if round_num == 3:
			# Diamond Ring for Round 3
			for z in range(4):
				for y in range(4):
					for x in range(4):
						var is_filled = false
						if y == 3: # Diamond on top
							is_filled = (x == 2 and z == 2)
						else: # Ring band
							var is_edge = (x == 0 or x == 3 or z == 0 or z == 3)
							var is_middle_height = (y == 1 or y == 2)
							is_filled = is_edge and is_middle_height
						target_solution[Vector3i(x, y, z)] = is_filled
		else:
			# Rose Shape for Round 4: Red rose petals top, green stem bottom
			for z in range(4):
				for y in range(4):
					for x in range(4):
						var is_filled = false
						if y >= 2: # Rose flower top
							is_filled = (x >= 1 and x <= 2) and (z >= 1 and z <= 2)
						else: # Stem
							is_filled = (x == 2 and z == 2) or (y == 1 and x == 1 and z == 2)
						target_solution[Vector3i(x, y, z)] = is_filled
	else:
		# Cupid Bow & Arrow for Boss Round 5 (5x5x5)
		for z in range(grid_size.z):
			for y in range(grid_size.y):
				for x in range(grid_size.x):
					var is_filled = (x == y) or (x + y == grid_size.x - 1) or (y == z)
					target_solution[Vector3i(x, y, z)] = is_filled



func _build_grid() -> void:
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			for z in range(grid_size.z):
				var pos = Vector3i(x, y, z)
				var block = block_scene.instantiate() as VoxelBlock
				add_child(block)
				block.set_grid_position(pos)
				block.set_meta("grid_pos", pos)
				# Center the grid slightly based on origin, or keep it 0-based
				block.position = Vector3(x, y, z) - Vector3(grid_size) / 2.0 + Vector3(0.5, 0.5, 0.5)
				blocks[pos] = block

func _on_slice_x_changed(value: float) -> void:
	slice_max.x = int(value)
	_update_slicing()
	_update_clues()

func _on_slice_y_changed(value: float) -> void:
	slice_max.y = int(value)
	_update_slicing()
	_update_clues()

func _on_slice_z_changed(value: float) -> void:
	slice_max.z = int(value)
	_update_slicing()
	_update_clues()

func _update_slicing() -> void:
	for pos in blocks.keys():
		var block = blocks[pos] as VoxelBlock

		# If it's outside the slice bounds, hide it
		if pos.x > slice_max.x or pos.y > slice_max.y or pos.z > slice_max.z:
			if block.current_state != block.BlockState.DESTROYED:
				block.set_state(block.BlockState.HIDDEN_BY_SLICE)
		else:
			# Only restore if it was previously hidden by slice, not if destroyed
			if block.current_state == block.BlockState.HIDDEN_BY_SLICE:
				block.set_state(block.BlockState.UNBROKEN)

func _update_clues() -> void:
	# Clear all block hints first
	for pos in blocks.keys():
		blocks[pos].clear_all_hints()

	# X clues (along X axis)
	for y in range(grid_size.y):
		for z in range(grid_size.z):
			var counts = _calculate_clue(Vector3i(0, y, z), Vector3i(1, 0, 0), grid_size.x)
			if counts.size() > 0:
				var hint_text = _format_hint_text(counts)
				var visible_blocks = []
				for x in range(grid_size.x):
					var pos = Vector3i(x, y, z)
					if blocks.has(pos):
						var block = blocks[pos]
						if block.current_state != block.BlockState.DESTROYED and block.current_state != block.BlockState.HIDDEN_BY_SLICE:
							visible_blocks.append(block)
				if visible_blocks.size() > 0:
					visible_blocks[0].set_face_hint(Vector3i(-1, 0, 0), hint_text)
					visible_blocks[-1].set_face_hint(Vector3i(1, 0, 0), hint_text)

	# Y clues (along Y axis)
	for x in range(grid_size.x):
		for z in range(grid_size.z):
			var counts = _calculate_clue(Vector3i(x, 0, z), Vector3i(0, 1, 0), grid_size.y)
			if counts.size() > 0:
				var hint_text = _format_hint_text(counts)
				var visible_blocks = []
				for y in range(grid_size.y):
					var pos = Vector3i(x, y, z)
					if blocks.has(pos):
						var block = blocks[pos]
						if block.current_state != block.BlockState.DESTROYED and block.current_state != block.BlockState.HIDDEN_BY_SLICE:
							visible_blocks.append(block)
				if visible_blocks.size() > 0:
					visible_blocks[0].set_face_hint(Vector3i(0, -1, 0), hint_text)
					visible_blocks[-1].set_face_hint(Vector3i(0, 1, 0), hint_text)

	# Z clues (along Z axis)
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var counts = _calculate_clue(Vector3i(x, y, 0), Vector3i(0, 0, 1), grid_size.z)
			if counts.size() > 0:
				var hint_text = _format_hint_text(counts)
				var visible_blocks = []
				for z in range(grid_size.z):
					var pos = Vector3i(x, y, z)
					if blocks.has(pos):
						var block = blocks[pos]
						if block.current_state != block.BlockState.DESTROYED and block.current_state != block.BlockState.HIDDEN_BY_SLICE:
							visible_blocks.append(block)
				if visible_blocks.size() > 0:
					visible_blocks[0].set_face_hint(Vector3i(0, 0, -1), hint_text)
					visible_blocks[-1].set_face_hint(Vector3i(0, 0, 1), hint_text)

func _format_hint_text(counts: Array) -> String:
	var sum = 0
	for c in counts:
		sum += c
	if counts.size() == 1:
		return str(sum)
	elif counts.size() == 2:
		return "(%d)" % sum
	else:
		return "[%d]" % sum

func _calculate_clue(start: Vector3i, step: Vector3i, length: int) -> Array:
	var groups = []
	var count = 0
	for i in range(length):
		var pos = start + step * i
		if target_solution.get(pos, false):
			count += 1
		else:
			if count > 0:
				groups.append(count)
				count = 0
	if count > 0:
		groups.append(count)
	return groups

# Signal handlers for MobileTouchControls
func on_chisel_requested(grid_pos: Vector3i) -> void:
	if not blocks.has(grid_pos):
		return
	var block = blocks[grid_pos] as VoxelBlock

	if block.current_state == block.BlockState.MARKED or block.current_state == block.BlockState.PAINTED:
		# Marked/Painted blocks are protected from chiseling
		if OS.has_feature("mobile"):
			Input.vibrate_handheld(20) # Small bump indicating protection
		return

	if block.current_state == block.BlockState.UNBROKEN:
		record_move(grid_pos, block.current_state)

		# If it's a target block, it's a mistake
		var is_target = false
		if voxel_states.has(grid_pos):
			is_target = voxel_states[grid_pos].get("is_target", false)

		if is_target:
			# Mistake: Force mark to prevent accidental destruction and preserve shape
			block.set_state(block.BlockState.MARKED)
			if voxel_states.has(grid_pos):
				voxel_states[grid_pos]["is_marked"] = true

			if is_tutorial:
				if OS.has_feature("mobile"):
					Input.vibrate_handheld(20)
				if camera:
					var pivot = camera.get_parent()
					while pivot != null and not pivot.has_method("shake"):
						pivot = pivot.get_parent()
					if pivot and pivot.has_method("shake"):
						pivot.shake(0.1, 0.1)
			else:
				_handle_mistake()
		else:
			if voxel_states.has(grid_pos):
				voxel_states[grid_pos]["is_chiseled"] = true
			destroy_block(block)
			if OS.has_feature("mobile"):
				Input.vibrate_handheld(40) # Haptic feedback on valid move
	elif block.current_state != block.BlockState.DESTROYED:
		if is_tutorial:
			if OS.has_feature("mobile"):
				Input.vibrate_handheld(20)
		else:
			_handle_mistake()

func on_mark_requested(grid_pos: Vector3i) -> void:
	if not blocks.has(grid_pos):
		return
	var block = blocks[grid_pos] as VoxelBlock

	if is_editor_mode:
		if block.current_state == block.BlockState.DESTROYED:
			record_move(grid_pos, block.current_state)
			block.set_state(block.BlockState.UNBROKEN)
			target_solution[grid_pos] = true
			_update_clues()
	else:
		if current_mode == EditMode.PAINT:
			if block.current_state == block.BlockState.UNBROKEN or block.current_state == block.BlockState.MARKED:
				record_move(grid_pos, block.current_state)
				block.set_state(block.BlockState.PAINTED)
				if OS.has_feature("mobile"):
					Input.vibrate_handheld(40)
			elif block.current_state == block.BlockState.PAINTED:
				record_move(grid_pos, block.current_state)
				block.set_state(block.BlockState.UNBROKEN)
				if OS.has_feature("mobile"):
					Input.vibrate_handheld(20)
		elif current_mode == EditMode.MARK:
			if block.current_state == block.BlockState.UNBROKEN or block.current_state == block.BlockState.PAINTED:
				record_move(grid_pos, block.current_state)
				block.set_state(block.BlockState.MARKED)
				if voxel_states.has(grid_pos):
					voxel_states[grid_pos]["is_marked"] = true
				if OS.has_feature("mobile"):
					Input.vibrate_handheld(40)
				emit_signal("voxel_marked", grid_pos)
			elif block.current_state == block.BlockState.MARKED:
				record_move(grid_pos, block.current_state)
				block.set_state(block.BlockState.UNBROKEN)
				if voxel_states.has(grid_pos):
					voxel_states[grid_pos]["is_marked"] = false
				if OS.has_feature("mobile"):
					Input.vibrate_handheld(20)
		else:
			if is_tutorial:
				if OS.has_feature("mobile"):
					Input.vibrate_handheld(20)
			else:
				_handle_mistake()

func _export_puzzle() -> void:
	var puzzle_data = {
		"dims": [grid_size.x, grid_size.y, grid_size.z],
		"cells": []
	}

	for z in range(grid_size.z):
		for y in range(grid_size.y):
			for x in range(grid_size.x):
				var pos = Vector3i(x, y, z)
				var state = 1 if target_solution.get(pos, false) else 0
				puzzle_data["cells"].append(state)

	var json_string = JSON.stringify(puzzle_data)
	print("EXPORTED JSON: ", json_string)

	# Try to save to user dir
	var file = FileAccess.open("user://exported_puzzle.json", FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("Saved puzzle to user://exported_puzzle.json")

func record_move(pos: Vector3i, previous_state: int) -> void:
	move_history.append({"pos": pos, "state": previous_state})
	emit_signal("history_updated", true)

func undo_last_move() -> void:
	if move_history.is_empty():
		return
	var last_move = move_history.pop_back()

	if typeof(last_move) == TYPE_ARRAY:
		for move in last_move:
			var pos = move["pos"]
			var prev_state = move["state"]
			if blocks.has(pos):
				var block = blocks[pos] as VoxelBlock
				block.set_state(prev_state)
	else:
		var pos = last_move["pos"]
		var prev_state = last_move["state"]
		if blocks.has(pos):
			var block = blocks[pos] as VoxelBlock
			block.set_state(prev_state)
	_update_slicing() # Ensure visibility is correct if hidden by slice
	emit_signal("history_updated", not move_history.is_empty())

func on_hover_requested(grid_pos: Vector3i, is_hover: bool) -> void:
	if not blocks.has(grid_pos):
		if hovered_block:
			hovered_block.set_highlight(false)
			hovered_block = null
		return

	var block = blocks[grid_pos] as VoxelBlock
	if is_hover:
		if hovered_block and hovered_block != block:
			hovered_block.set_highlight(false)
		hovered_block = block
		hovered_block.set_highlight(true)
	else:
		if hovered_block == block:
			hovered_block.set_highlight(false)
			hovered_block = null

func _handle_mistake() -> void:
	mistakes += 1
	combo = 0
	player_hp -= 1
	_update_ui_state()
	emit_signal("mistake_made", mistakes)

	if hp_label:
		# Visual juice for player taking damage
		hp_label.pivot_offset = hp_label.size / 2
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(hp_label, "modulate", Color(1, 0, 0, 1), 0.1)
		tween.tween_property(hp_label, "scale", Vector2(1.5, 1.5), 0.1)
		tween.chain().tween_property(hp_label, "modulate", Color(1, 1, 1, 1), 0.2)
		tween.parallel().tween_property(hp_label, "scale", Vector2(1, 1), 0.2)

	if OS.has_feature("mobile"):
		Input.vibrate_handheld(120)
	if camera:
		var pivot = camera.get_parent()
		while pivot != null and not pivot.has_method("shake"):
			pivot = pivot.get_parent()
		if pivot and pivot.has_method("shake"):
			pivot.shake(0.3, 0.2)

	if player_hp <= 0:
		is_puzzle_active = false
		emit_signal("game_over")
		print("Game Over! Restarting floor.")
		await get_tree().create_timer(2.0).timeout
		base_grid_size = 3
		current_floor = 1
		start_level()

func destroy_block(block: VoxelBlock) -> void:
	block.set_state(block.BlockState.DESTROYED)
	if is_player_action:
		combo += 1
		_update_ui_state()
		if combo_label:
			combo_label.pivot_offset = combo_label.size / 2
			var tween = create_tween()
			tween.set_parallel(true)
			tween.tween_property(combo_label, "scale", Vector2(1.5, 1.5), 0.1)
			tween.tween_property(combo_label, "modulate", Color(1.0, 0.84, 0.0, 1.0), 0.1) # Gold
			tween.chain().tween_property(combo_label, "scale", Vector2(1, 1), 0.2)
			tween.parallel().tween_property(combo_label, "modulate", Color(1, 1, 1, 1), 0.2)
	_check_win_condition()
	emit_signal("block_destroyed", block.grid_position, is_player_action)

func _check_win_condition() -> void:
	if not is_puzzle_active: return

	if player_hp <= 0:
		return

	var non_target_remaining = 0

	# Win condition: All non-target blocks are chiseled (destroyed)
	for pos in voxel_states.keys():
		var state = voxel_states[pos]
		if not state["is_target"] and not state["is_chiseled"]:
			# Ensure it actually isn't destroyed in the block state just in case
			if blocks.has(pos) and blocks[pos].current_state != blocks[pos].BlockState.DESTROYED:
				non_target_remaining += 1

	if non_target_remaining > 0:
		return

	# Puzzle Solved!
	is_puzzle_active = false
	print("Puzzle Solved! Revealing model...")

	# Prepare payload for Masquerade Painting mode if supported
	var payload = {
		"target_shape": target_shape.duplicate(),
		"grid_size": grid_size
	}

	if is_instance_valid(GameManager) and "MASQUERADE_PAINTING" in GameManager.GameMode:
		GameManager.switch_mode(GameManager.GameMode.MASQUERADE_PAINTING, payload)
	else:
		_reveal_model()

func _reveal_model() -> void:
	# Hide all slice constraints
	if slice_controls:
		slice_controls.hide()
	slice_max = grid_size
	_update_slicing()

	# Clear clues and disable outlines for a clean sculpture look
	for pos in blocks.keys():
		blocks[pos].clear_all_hints()
		blocks[pos].disable_outline()



	# Restyle background color dynamically to pastel pink
	var env = get_node_or_null("WorldEnvironment")
	if env and env.environment:
		pass

	# Smooth in-place wave scale transition
	for pos in blocks.keys():
		var block = blocks[pos]
		if block.current_state != block.BlockState.DESTROYED and block.current_state != block.BlockState.HIDDEN_BY_SLICE:
			var delay = float(pos.x + pos.y + pos.z) * 0.05
			var tween = create_tween()
			tween.tween_interval(delay)
			tween.tween_property(block, "scale", Vector3(1.2, 1.2, 1.2), 0.15).set_trans(Tween.TRANS_SINE)
			tween.tween_property(block, "scale", Vector3(1.0, 1.0, 1.0), 0.15).set_trans(Tween.TRANS_SINE)

	# Start camera orbit
	if camera:
		var pivot = camera.get_parent()
		if pivot and pivot.has_method("add_orbit_input"):
			var spin_time = 10.0
			var tween = create_tween()
			tween.tween_property(pivot, "target_yaw", pivot.target_yaw + deg_to_rad(360.0), spin_time).set_trans(Tween.TRANS_SINE)

	# Detect round from EscapeGauntlet if active
	var round_num = 1
	var gauntlet = get_parent()
	if gauntlet and gauntlet.name == "EscapeGauntlet" and "current_round" in gauntlet:
		round_num = gauntlet.current_round

	var puzzle_name = ""
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.get("mode_payload") and game_manager.mode_payload.has("custom_puzzle"):
		puzzle_name = game_manager.mode_payload["custom_puzzle"].get("name", "")
	elif not has_custom_puzzle:
		if round_num == 1:
			puzzle_name = "Heart"
		elif round_num == 2:
			puzzle_name = "Love Letter"
		elif round_num == 3:
			puzzle_name = "Diamond Ring"
		elif round_num == 4:
			puzzle_name = "Rose"
		else:
			puzzle_name = "Cupid's Bow & Arrow"

	# Subject color palette matching Valentine themes
	var puzzle_colors = {
		"Heart": Color(0.95, 0.15, 0.35, 1.0),            # Ruby Red
		"Love Letter": Color(0.95, 0.95, 0.85, 1.0),       # Cream Paper
		"Diamond Ring": Color(1.0, 0.84, 0.0, 1.0),        # Gold
		"Rose": Color(0.85, 0.1, 0.2, 1.0),                # Crimson Red
		"Cupid's Bow & Arrow": Color(0.95, 0.5, 0.6, 1.0), # Rose Pink
		"Horse": Color(0.55, 0.35, 0.2, 1.0),
		"Platypus": Color(0.1, 0.45, 0.45, 1.0),
		"Suzanne": Color(0.65, 0.65, 0.65, 1.0),
		"Pyramid": Color(0.85, 0.75, 0.45, 1.0),
		"Sphinx": Color(0.85, 0.75, 0.45, 1.0),
		"Chair": Color(0.5, 0.3, 0.15, 1.0),
		"Computer": Color(0.75, 0.75, 0.75, 1.0),
		"Strange tree": Color(0.15, 0.55, 0.15, 1.0),
		"Simple hints": Color(0.8, 0.4, 0.4, 1.0),
	}

	var sculpture_color = puzzle_colors.get(puzzle_name, Color(0.95, 0.45, 0.55, 1.0)) # Romantic Pinkish-Red by default

	# Color the final sculpture
	for pos in target_solution.keys():
		if target_solution[pos] and blocks.has(pos):
			var block = blocks[pos] as VoxelBlock
			block.base_material.albedo_color = sculpture_color

	# Deal damage to Boss (if in endless gauntlet mode)
	var time_bonus = max(0.0, 60.0 - time_elapsed) * 2.0
	var combo_bonus = combo * 5.0
	var damage = 50.0 + time_bonus + combo_bonus
	boss_hp -= damage
	_update_ui_state()

	# Wait a short moment to show the pure 3D model
	await get_tree().create_timer(2.0).timeout

	# Create and show high-fidelity Victory Screen
	_show_victory_screen(puzzle_name)


func _show_victory_screen(puzzle_name: String) -> void:
	var stats = preload("res://scripts/stats.gd").new()
	stats.time_seconds = time_elapsed
	stats.current_level_string = "Endless " + str(current_floor) + " - " + puzzle_name if not has_custom_puzzle else puzzle_name

	# Calculate a raw score based on time and mistakes
	var base_score = 10000
	var time_penalty = int(time_elapsed * 10)
	var mistake_penalty = mistakes * 500
	stats.raw_score = max(0, base_score - time_penalty - mistake_penalty)
	
	# Calculate stars earned
	if mistakes == 0 and time_elapsed < 120.0:
		stats.stars_earned = 3
	elif mistakes <= 1 and time_elapsed < 300.0:
		stats.stars_earned = 2
	else:
		stats.stars_earned = 1

	var victory_scene = preload("res://scenes/victory_screen.tscn").instantiate()
	var canvas_layer = get_node_or_null("CanvasLayer")
	if canvas_layer:
		canvas_layer.add_child(victory_scene)
		victory_scene.initialize(stats)
		victory_scene.start_next_nonogram_requested.connect(_on_next_level_requested.bind(victory_scene))
		victory_scene.leave_requested.connect(_on_leave_requested)

func _on_leave_requested() -> void:
	if get_node_or_null("/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet"):
		var gauntlet = get_node("/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet")
		var confirm = gauntlet.get_node_or_null("CanvasLayer/UI/ConfirmDialog")
		if confirm:
			confirm.show()
	else:
		get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.MAIN_MENU)


func _on_next_level_requested(victory_scene: Node) -> void:
	victory_scene.queue_free()
	emit_signal("puzzle_solved")

	if has_custom_puzzle:
		get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.PUZZLE_SELECTION)
	else:
		if boss_hp <= 0:
			print("Boss Defeated! Advancing floor.")
			current_floor += 1
			base_grid_size = min(base_grid_size + 1, 5)
			emit_signal("floor_cleared")
			start_level()
		else:
			print("Next phase of the boss!")
			start_level()

