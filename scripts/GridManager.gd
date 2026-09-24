extends Node3D

class_name GridManager

const VoxelLogicSolver = preload("res://scripts/VoxelLogicSolver.gd")
const PuzzleDataValidator = preload("res://scripts/PuzzleDataValidator.gd")
const DEFAULT_PANORAMA: Texture2D = preload("res://assets/textures/generated/abstract_panorama.svg")

@export var grid_size: Vector3i = Vector3i(5, 5, 5)

@export var block_scene: PackedScene = preload("res://scenes/Block.tscn")
@export var camera: Camera3D

# MultiMesh Integration
var multimesh_outline: MultiMeshInstance3D
var multimesh_unbroken: MultiMeshInstance3D
var multimesh_marked: MultiMeshInstance3D
var multimesh_highlight: MultiMeshInstance3D
var multimesh_ghost: MultiMeshInstance3D

var hovered_block: Node3D = null # We'll replace this with hovered_pos
var hovered_pos: Vector3i = Vector3i(-1, -1, -1)


# Cell state enum (Single source of truth)
enum CellState {
	UNBROKEN,
	MARKED,
	DESTROYED,
	PAINTED
}

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
signal cell_state_changed(pos: Vector3i, new_state: CellState)

var mistakes: int = 0
var combo: int = 0
var player_hp: int = 3
var boss_hp: float = 100.0
var max_boss_hp: float = 100.0
var current_floor: int = 1
var custom_puzzle_data: Dictionary = {}

func is_target_cell(pos: Vector3i) -> bool:
	return target_solution.get(pos, false)

func is_cell_correct(pos: Vector3i) -> bool:
	if not voxel_states.has(pos):
		return false
	var is_target: bool = is_target_cell(pos)
	var state: CellState = voxel_states[pos].get("cell_state", CellState.UNBROKEN)

	if is_target:
		# Filled target voxel: MUST NOT be destroyed
		return state != CellState.DESTROYED
	else:
		# Empty space voxel: MUST be destroyed (chiseled away)
		return state == CellState.DESTROYED

func is_cell_chiseled(pos: Vector3i) -> bool:
	return voxel_states.has(pos) and int(voxel_states[pos].get("cell_state", CellState.UNBROKEN)) == CellState.DESTROYED

func is_cell_marked(pos: Vector3i) -> bool:
	return voxel_states.has(pos) and int(voxel_states[pos].get("cell_state", CellState.UNBROKEN)) == CellState.MARKED

func is_cell_painted(pos: Vector3i) -> bool:
	return voxel_states.has(pos) and int(voxel_states[pos].get("cell_state", CellState.UNBROKEN)) == CellState.PAINTED

func is_cell_unbroken(pos: Vector3i) -> bool:
	return voxel_states.has(pos) and int(voxel_states[pos].get("cell_state", CellState.UNBROKEN)) == CellState.UNBROKEN

func is_cell_interactable(pos: Vector3i) -> bool:
	if not voxel_states.has(pos):
		return false
	var state: Dictionary = voxel_states[pos]
	return not state.get("is_hidden_by_slice", false) and int(state.get("cell_state", CellState.UNBROKEN)) != CellState.DESTROYED

func mark_cell(pos: Vector3i) -> bool:
	if not voxel_states.has(pos):
		return false
	var state: Dictionary = voxel_states[pos]
	if state.get("is_hidden_by_slice", false) or is_cell_chiseled(pos) or is_cell_painted(pos):
		return false
	var current_state: CellState = int(state.get("cell_state", CellState.UNBROKEN))
	if current_state != CellState.UNBROKEN and current_state != CellState.MARKED:
		return false
	var new_state: CellState = CellState.MARKED if current_state == CellState.UNBROKEN else CellState.UNBROKEN
	_set_canonical_cell_state(pos, new_state)
	return true

func paint_cell(pos: Vector3i) -> bool:
	if not voxel_states.has(pos):
		return false
	var state: Dictionary = voxel_states[pos]
	if state.get("is_hidden_by_slice", false) or is_cell_chiseled(pos) or is_cell_marked(pos):
		return false
	var current_state: CellState = int(state.get("cell_state", CellState.UNBROKEN))
	if current_state != CellState.UNBROKEN and current_state != CellState.PAINTED:
		return false
	var new_state: CellState = CellState.PAINTED if current_state == CellState.UNBROKEN else CellState.UNBROKEN
	_set_canonical_cell_state(pos, new_state)
	return true

func hammer_cell(pos: Vector3i) -> bool:
	if not voxel_states.has(pos):
		return false
	var state: Dictionary = voxel_states[pos]
	if state.get("is_hidden_by_slice", false) or is_cell_chiseled(pos):
		return false
	_set_canonical_cell_state(pos, CellState.DESTROYED)
	return true

func _set_canonical_cell_state(pos: Vector3i, new_state: CellState) -> void:
	if not voxel_states.has(pos):
		return
	var state: Dictionary = voxel_states[pos]
	state["cell_state"] = new_state
	state["is_painted"] = new_state == CellState.PAINTED
	_sync_block_state(pos)
	cell_state_changed.emit(pos, new_state)
	_update_multimesh()
	_update_clues()
	_check_win_condition()

func _sync_block_state(pos: Vector3i) -> void:
	var block := blocks.get(pos) as VoxelBlock
	if not block:
		return
	if not voxel_states.has(pos):
		block.set_state(block.BlockState.DESTROYED)
		return
	var state: Dictionary = voxel_states[pos]
	if state.get("is_hidden_by_slice", false):
		block.set_state(block.BlockState.HIDDEN_BY_SLICE)
		return
	var cell_state: CellState = int(state.get("cell_state", CellState.UNBROKEN))
	match cell_state:
		CellState.MARKED:
			block.set_state(block.BlockState.MARKED)
		CellState.DESTROYED:
			block.set_state(block.BlockState.DESTROYED)
		CellState.PAINTED:
			block.set_state(block.BlockState.PAINTED)
		_:
			block.set_state(block.BlockState.UNBROKEN)

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
@onready var paint_btn: Button = null
@onready var mark_btn: Button = null
@onready var rotate_btn: Button = null
@onready var slice_toggle_btn: Button = null
@onready var undo_btn: Button = null
@onready var hint_btn: Button = null
@onready var export_btn: Button = null

@onready var round_label: Label = null
@onready var hp_label: Label = null
@onready var combo_label: Label = null
@onready var timer_label: Label = null
@onready var boss_name_label: Label = null
@onready var boss_hp_bar: ProgressBar = null
@onready var leave_btn: Button = null

enum EditMode { DESTROY, MARK, ROTATE, BUILD, PAINT }
var current_mode: EditMode = EditMode.DESTROY
var is_editor_mode: bool = false
enum HintType { SIMPLE, CIRCLE, SQUARE }

const GameManagerClass = preload("res://scripts/GameManager.gd")

var has_custom_puzzle: bool = false
var is_tutorial: bool = false
var tutorial_manager: TutorialManager = null
var tutorial_ui: CanvasLayer = null
var input_locked: bool = false
var puzzle_solved_emitted: bool = false
var touch_controls: MobileTouchControls = null
var local_confirm_dialog: Control = null

func _ready() -> void:
	var env_node := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node and env_node.environment and env_node.environment.sky and env_node.environment.sky.sky_material is PanoramaSkyMaterial:
		(env_node.environment.sky.sky_material as PanoramaSkyMaterial).panorama = DEFAULT_PANORAMA


	# Initialize MultiMesh batching
	_setup_multimesh()

	var game_manager := get_node_or_null("/root/GameManager")

	if not custom_puzzle_data.is_empty():
		has_custom_puzzle = true

	if game_manager:
		var mode_payload_value: Variant = game_manager.get("mode_payload")
		var mode_payload: Dictionary = mode_payload_value if mode_payload_value is Dictionary else {}
		if mode_payload.get("mode") == "editor":
			is_editor_mode = true
		if mode_payload.has("custom_puzzle"):
			has_custom_puzzle = true
			custom_puzzle_data = mode_payload["custom_puzzle"]

	# Find UI elements
	slice_controls = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/SliceControls")
	if slice_controls:
		slice_slider_x = slice_controls.get_node_or_null("SliderX")
		slice_slider_y = slice_controls.get_node_or_null("SliderY")
		slice_slider_z = slice_controls.get_node_or_null("SliderZ")

	chisel_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/ChiselButton")
	paint_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/PaintButton")
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

	leave_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/TopRowContainer/LeaveButton")
	if not leave_btn:
		leave_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/TopInfoBar/HBoxContainer/LeaveButton")

	if leave_btn and not leave_btn.pressed.is_connected(_on_leave_requested):
		leave_btn.pressed.connect(_on_leave_requested)

	var top_info = get_node_or_null("CanvasLayer/Control/MarginContainer/TopRowContainer/TopInfoBar/HBoxContainer")
	if not top_info:
		top_info = get_node_or_null("CanvasLayer/Control/MarginContainer/TopInfoBar/HBoxContainer")

	if top_info:
		round_label = top_info.get_node_or_null("RoundLabel")
		hp_label = top_info.get_node_or_null("HPLabel")
		combo_label = top_info.get_node_or_null("ComboLabel")
		timer_label = top_info.get_node_or_null("TimerLabel")

		var boss_container = top_info.get_node_or_null("BossContainer")
		if boss_container:
			boss_name_label = boss_container.get_node_or_null("BossNameLabel")
			boss_hp_bar = boss_container.get_node_or_null("BossHPBar")

	start_level()

	touch_controls = get_node_or_null("CanvasLayer/Control") as MobileTouchControls
	if touch_controls:
		touch_controls.set_grid_manager(self)
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
	hint_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/HintButton")
	if hint_btn and not hint_btn.pressed.is_connected(_on_hint_pressed):
		hint_btn.pressed.connect(_on_hint_pressed)
	var hint_mechanic := get_node_or_null("CooldownHintMechanic") as CooldownHintMechanic
	if hint_mechanic:
		if not hint_mechanic.hint_ready.is_connected(_on_hint_ready):
			hint_mechanic.hint_ready.connect(_on_hint_ready)
		if not hint_mechanic.cooldown_updated.is_connected(_on_hint_cooldown):
			hint_mechanic.cooldown_updated.connect(_on_hint_cooldown)
	if export_btn and not export_btn.pressed.is_connected(_export_puzzle):
		export_btn.pressed.connect(_export_puzzle)
	_update_ui_state()

func _on_hint_pressed() -> void:
	var mechanic := get_node_or_null("CooldownHintMechanic") as CooldownHintMechanic
	if not mechanic or not _can_edit_grid():
		return
	if not mechanic.use_hint():
		_play_ui_sound("error")
		return
	_update_hint_ui()

func _on_hint_ready() -> void:
	_update_hint_ui()

func _on_hint_cooldown(time_left: float) -> void:
	if hint_btn:
		hint_btn.text = "Hint %.0fs" % ceil(maxf(time_left, 0.0))
		hint_btn.tooltip_text = "Hint ready in %.1f seconds" % maxf(time_left, 0.0)

func _update_hint_ui() -> void:
	if not hint_btn:
		return
	var mechanic := get_node_or_null("CooldownHintMechanic") as CooldownHintMechanic
	if mechanic and not mechanic.is_ready:
		hint_btn.text = "Hint %.0fs" % ceil(mechanic.get_cooldown_remaining())
		hint_btn.disabled = true
	else:
		hint_btn.text = "Hint"
		hint_btn.disabled = input_locked or not is_puzzle_active

func _load_custom_puzzle(puzzle_data: Dictionary) -> void:
	var analysis: Dictionary = PuzzleDataValidator.analyze_puzzle(puzzle_data, true, true)
	if not bool(analysis.get("ok", false)):
		push_warning("Rejected invalid custom puzzle '%s': %s" % [puzzle_data.get("id", puzzle_data.get("name", "unknown")), str(analysis.get("errors", []))])
		has_custom_puzzle = false
		custom_puzzle_data = {}
		grid_size = Vector3i(base_grid_size, base_grid_size, base_grid_size)
		slice_max = grid_size - Vector3i.ONE
		_clear_grid_blocks()
		_generate_solution()
		_initialize_grid_state()
		_build_grid()
		_update_slicing()
		_update_clues()
		_fit_camera_to_grid()
		_check_win_condition()
		return

	custom_puzzle_data = (analysis.get("puzzle", {}) as Dictionary).duplicate(true)
	var canonical_solution: Dictionary = analysis.get("solution", {})
	var dims_array: Array = custom_puzzle_data.get("dims", [3, 3, 3])
	grid_size = Vector3i(int(dims_array[0]), int(dims_array[1]), int(dims_array[2]))
	slice_max = grid_size - Vector3i.ONE
	target_solution.clear()
	for coordinate: Vector3i in canonical_solution.keys():
		target_solution[coordinate] = bool(canonical_solution[coordinate])

	_clear_grid_blocks()
	_initialize_grid_state()
	_build_grid()
	_setup_tutorial(custom_puzzle_data)
	_update_slicing()
	_update_clues()
	_update_ui_state()
	_fit_camera_to_grid()
	_check_win_condition()

func _clear_grid_blocks() -> void:
	for block: VoxelBlock in blocks.values():
		if is_instance_valid(block):
			block.queue_free()
	blocks.clear()

func _initialize_grid_state() -> void:
	target_shape.clear()
	voxel_states.clear()
	move_history.clear()
	for z: int in range(grid_size.z):
		for y: int in range(grid_size.y):
			for x: int in range(grid_size.x):
				var pos := Vector3i(x, y, z)
				var is_target: bool = is_target_cell(pos)
				if is_target:
					target_shape.append(pos)
				voxel_states[pos] = {
					"is_target": is_target,
					"cell_state": CellState.UNBROKEN,
					"is_painted": false,
					"is_hidden_by_slice": false
				}

func _setup_tutorial(puzzle_data: Dictionary) -> void:
	is_tutorial = puzzle_data.get("theme") == "tutorial" or puzzle_data.get("id") == "tutorial_star"
	if not is_tutorial:
		return
	if not is_instance_valid(tutorial_manager):
		tutorial_manager = TutorialManager.new()
		tutorial_manager.grid_manager = self
		add_child(tutorial_manager)
	else:
		tutorial_manager.grid_manager = self
	if not is_instance_valid(tutorial_ui):
		var tutorial_ui_scene: PackedScene = load("res://scenes/TutorialUI.tscn")
		if tutorial_ui_scene:
			tutorial_ui = tutorial_ui_scene.instantiate() as CanvasLayer
			add_child(tutorial_ui)
			tutorial_ui.call("setup", tutorial_manager)
	if touch_controls and not touch_controls.camera_rotated.is_connected(tutorial_manager.on_camera_rotated):
		touch_controls.camera_rotated.connect(tutorial_manager.on_camera_rotated)
	if slice_slider_y and not slice_slider_y.value_changed.is_connected(_on_tutorial_layer_slider_changed):
		slice_slider_y.value_changed.connect(_on_tutorial_layer_slider_changed)
	if not block_destroyed.is_connected(tutorial_manager.on_voxel_chiseled):
		block_destroyed.connect(tutorial_manager.on_voxel_chiseled)
	if not voxel_marked.is_connected(tutorial_manager.on_voxel_marked):
		voxel_marked.connect(tutorial_manager.on_voxel_marked)
	if not puzzle_solved.is_connected(tutorial_manager.on_puzzle_solved):
		puzzle_solved.connect(tutorial_manager.on_puzzle_solved)

func _on_tutorial_layer_slider_changed(value: float) -> void:
	if is_instance_valid(tutorial_manager):
		tutorial_manager.on_layer_slider_changed("Y", int(value))


func start_level() -> void:
	is_puzzle_active = true
	puzzle_solved_emitted = false
	input_locked = false
	start_time = Time.get_ticks_msec()
	mistakes = 0
	combo = 0
	player_hp = 3
	move_history.clear()

	# Clear old blocks and targets.
	_clear_grid_blocks()
	target_solution.clear()

	grid_size = Vector3i(base_grid_size, base_grid_size, base_grid_size)
	slice_max = grid_size - Vector3i(1, 1, 1)

	max_boss_hp = 100.0 + (current_floor * 50.0)
	boss_hp = max_boss_hp


	# Initialize MultiMesh batching
	_setup_multimesh()

	if has_custom_puzzle and not custom_puzzle_data.is_empty():
		_load_custom_puzzle(custom_puzzle_data)
		return

	_generate_solution()
	_initialize_grid_state()
	_build_grid()

	_update_slicing()

	_update_clues()

	_fit_camera_to_grid()

	# Find UI elements
	slice_controls = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/SliceControls")
	if slice_controls:
		slice_slider_x = slice_controls.get_node_or_null("SliderX")
		slice_slider_y = slice_controls.get_node_or_null("SliderY")
		slice_slider_z = slice_controls.get_node_or_null("SliderZ")

	chisel_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/ChiselButton")
	paint_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/PaintButton")
	mark_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/MarkButton")
	rotate_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/RotateButton")
	slice_toggle_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/SliceToggleButton")
	undo_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/UndoButton")
	hint_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/HintButton")
	export_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/ExportButton")

	var top_info = get_node_or_null("CanvasLayer/Control/MarginContainer/TopRowContainer/TopInfoBar/HBoxContainer")
	if not top_info:
		top_info = get_node_or_null("CanvasLayer/Control/MarginContainer/TopInfoBar/HBoxContainer")

	var leave_b = get_node_or_null("CanvasLayer/Control/MarginContainer/TopRowContainer/LeaveButton")
	if not leave_b and top_info:
		leave_b = top_info.get_node_or_null("LeaveButton")
	if leave_b and not leave_b.pressed.is_connected(_on_leave_requested):
		leave_b.pressed.connect(_on_leave_requested)

	if top_info:
		round_label = top_info.get_node_or_null("RoundLabel")
		hp_label = top_info.get_node_or_null("HPLabel")
		combo_label = top_info.get_node_or_null("ComboLabel")
		timer_label = top_info.get_node_or_null("TimerLabel")

		var boss_container = top_info.get_node_or_null("BossContainer")
		if boss_container:
			boss_name_label = boss_container.get_node_or_null("BossNameLabel")
			boss_hp_bar = boss_container.get_node_or_null("BossHPBar")

	# Connect UI

	if slice_slider_x:
		slice_slider_x.max_value = grid_size.x - 1
		slice_slider_x.value = grid_size.x - 1
		if not slice_slider_x.value_changed.is_connected(_on_slice_x_changed):
			slice_slider_x.value_changed.connect(_on_slice_x_changed)
	if slice_slider_y:
		slice_slider_y.max_value = grid_size.y - 1
		slice_slider_y.value = grid_size.y - 1
		if not slice_slider_y.value_changed.is_connected(_on_slice_y_changed):
			slice_slider_y.value_changed.connect(_on_slice_y_changed)
	if slice_slider_z:
		slice_slider_z.max_value = grid_size.z - 1
		slice_slider_z.value = grid_size.z - 1
		if not slice_slider_z.value_changed.is_connected(_on_slice_z_changed):
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
	if hint_btn and not hint_btn.pressed.is_connected(_on_hint_pressed):
		hint_btn.pressed.connect(_on_hint_pressed)

	_update_ui_state()

	_fit_camera_to_grid()

func _fit_camera_to_grid() -> void:
	if not camera:
		return
	var pivot := camera.get_parent()
	while pivot and not pivot is CameraPivotController:
		pivot = pivot.get_parent()
	if pivot is CameraPivotController:
		(pivot as CameraPivotController).fit_to_grid(grid_size)
	elif camera:
		camera.position.z = maxf(Vector3(grid_size).length() * 1.2, 4.0)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo:
		return
	var key_event := event as InputEventKey
	if key_event.keycode != KEY_ESCAPE and not _can_edit_grid():
		return
	match key_event.keycode:
		KEY_ESCAPE:
			_on_leave_requested()
		KEY_1:
			_on_chisel_mode_selected()
		KEY_2:
			_on_mark_mode_selected()
		KEY_Q:
			_on_chisel_mode_selected()
		KEY_E:
			_on_mark_mode_selected()
		KEY_S:
			_on_slice_toggle_pressed()
		KEY_H:
			_on_hint_pressed()
		KEY_Z:
			if key_event.ctrl_pressed:
				undo_last_move()
	if is_puzzle_active:
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if is_puzzle_active:
		time_elapsed = (Time.get_ticks_msec() - start_time) / 1000.0
		if timer_label:
			timer_label.text = "Time: %.1f" % time_elapsed

func _update_ui_state() -> void:
	if hp_label:
		var gauntlet := get_parent()
		var max_hp: int = 3
		if gauntlet and "max_mistakes" in gauntlet:
			max_hp = int(gauntlet.get("max_mistakes"))
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

	var controls_disabled: bool = input_locked or not is_puzzle_active
	if chisel_btn:
		chisel_btn.disabled = controls_disabled
		chisel_btn.button_pressed = current_mode == EditMode.DESTROY
	if paint_btn:
		paint_btn.disabled = controls_disabled
		paint_btn.button_pressed = current_mode == EditMode.PAINT
	if mark_btn:
		mark_btn.disabled = controls_disabled
		mark_btn.button_pressed = current_mode == EditMode.MARK or current_mode == EditMode.BUILD
	if rotate_btn:
		rotate_btn.disabled = controls_disabled
		rotate_btn.button_pressed = current_mode == EditMode.ROTATE
	if slice_toggle_btn:
		slice_toggle_btn.disabled = controls_disabled
	if undo_btn:
		undo_btn.disabled = controls_disabled or move_history.is_empty()
	if hint_btn:
		hint_btn.disabled = controls_disabled
	if export_btn:
		export_btn.disabled = not is_editor_mode
	for slider: HSlider in [slice_slider_x, slice_slider_y, slice_slider_z]:
		if slider:
			slider.editable = not controls_disabled
	if touch_controls:
		touch_controls.input_locked = controls_disabled
		touch_controls.set_touch_mode(_touch_mode_for_current_mode())
	_update_hint_ui()

func _touch_mode_for_current_mode() -> MobileTouchControls.TouchMode:
	match current_mode:
		EditMode.MARK, EditMode.BUILD:
			return MobileTouchControls.TouchMode.MARK
		EditMode.ROTATE:
			return MobileTouchControls.TouchMode.ROTATE
		EditMode.PAINT:
			return MobileTouchControls.TouchMode.PAINT
		_:
			return MobileTouchControls.TouchMode.CHISEL

func set_input_locked(locked: bool) -> void:
	input_locked = locked
	_update_ui_state()

func _can_edit_grid() -> bool:
	return is_puzzle_active and not input_locked and not puzzle_solved_emitted

func _on_chisel_mode_selected() -> void:
	if current_mode == EditMode.DESTROY:
		return
	current_mode = EditMode.DESTROY
	_play_ui_sound("toggle")
	_update_ui_state()

func _on_paint_mode_selected() -> void:
	current_mode = EditMode.PAINT if not is_editor_mode else EditMode.BUILD
	_play_ui_sound("toggle")
	_update_ui_state()

func _on_mark_mode_selected() -> void:
	current_mode = EditMode.MARK if not is_editor_mode else EditMode.BUILD
	_play_ui_sound("toggle")
	_update_ui_state()

func _on_rotate_mode_selected() -> void:
	current_mode = EditMode.ROTATE
	_play_ui_sound("toggle")
	_update_ui_state()

func _on_slice_toggle_pressed() -> void:
	if not _can_edit_grid():
		return
	if slice_controls:
		slice_controls.visible = not slice_controls.visible
		slice_toggle_btn.set_pressed_no_signal(slice_controls.visible)

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
		# Small test/editor grids use a checkerboard so they always contain
		# both target and empty cells. Larger fallback rounds use the Cupid bow.
		for z in range(grid_size.z):
			for y in range(grid_size.y):
				for x in range(grid_size.x):
					var is_filled: bool
					if grid_size == Vector3i(2, 2, 2):
						is_filled = (x + y + z) % 2 == 0
					else:
						is_filled = (x == y) or (x + y == grid_size.x - 1) or (y == z)
					target_solution[Vector3i(x, y, z)] = is_filled



func _build_grid() -> void:
	# Blocks are now managed entirely by state dict (voxel_states) and MultiMesh.
	# But we still need individual nodes for labels (hints). We'll keep lightweight dummy nodes for now, or just use VoxelBlock since they have Label3D setup.
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			for z in range(grid_size.z):
				var pos = Vector3i(x, y, z)

				# Initialize state
				voxel_states[pos] = {
					"is_target": target_solution.get(pos, false),
					"cell_state": CellState.UNBROKEN,
					"is_painted": false,
					"is_hidden_by_slice": false
				}

				# Keep Block scene ONLY for the Label3D hints.
				# We hide its MeshInstance and disable its collision.
				var block = block_scene.instantiate() as VoxelBlock
				add_child(block)
				block.set_grid_position(pos)
				block.set_meta("grid_pos", pos)
				block.position = Vector3(x, y, z) - Vector3(grid_size) / 2.0 + Vector3(0.5, 0.5, 0.5)

				# Disable physical rendering/collision
				if block.has_node("MeshInstance3D"):
					block.get_node("MeshInstance3D").hide()
				if block.has_node("CollisionShape3D"):
					block.get_node("CollisionShape3D").disabled = true

				blocks[pos] = block

	_update_multimesh()

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
	for pos: Vector3i in voxel_states.keys():
		var state: Dictionary = voxel_states[pos]
		var should_hide: bool = pos.x > slice_max.x or pos.y > slice_max.y or pos.z > slice_max.z
		state["is_hidden_by_slice"] = should_hide and not is_cell_chiseled(pos)
		_sync_block_state(pos)
	_update_multimesh()

func _update_clues() -> void:
	for block: VoxelBlock in blocks.values():
		block.clear_all_hints()

	for y: int in range(grid_size.y):
		for z: int in range(grid_size.z):
			var counts: Array = _calculate_clue(Vector3i(0, y, z), Vector3i(1, 0, 0), grid_size.x)
			var visible_blocks: Array[VoxelBlock] = []
			for x: int in range(grid_size.x):
				var pos := Vector3i(x, y, z)
				if is_cell_interactable(pos):
					visible_blocks.append(blocks[pos] as VoxelBlock)
			if not visible_blocks.is_empty():
				var hint_text: String = _format_hint_text(counts)
				visible_blocks[0].set_face_hint(Vector3i(-1, 0, 0), hint_text)
				visible_blocks[-1].set_face_hint(Vector3i(1, 0, 0), hint_text)

	for x: int in range(grid_size.x):
		for z: int in range(grid_size.z):
			var counts: Array = _calculate_clue(Vector3i(x, 0, z), Vector3i(0, 1, 0), grid_size.y)
			var visible_blocks: Array[VoxelBlock] = []
			for y: int in range(grid_size.y):
				var pos := Vector3i(x, y, z)
				if is_cell_interactable(pos):
					visible_blocks.append(blocks[pos] as VoxelBlock)
			if not visible_blocks.is_empty():
				var hint_text: String = _format_hint_text(counts)
				visible_blocks[0].set_face_hint(Vector3i(0, -1, 0), hint_text)
				visible_blocks[-1].set_face_hint(Vector3i(0, 1, 0), hint_text)

	for x: int in range(grid_size.x):
		for y: int in range(grid_size.y):
			var counts: Array = _calculate_clue(Vector3i(x, y, 0), Vector3i(0, 0, 1), grid_size.z)
			var visible_blocks: Array[VoxelBlock] = []
			for z: int in range(grid_size.z):
				var pos := Vector3i(x, y, z)
				if is_cell_interactable(pos):
					visible_blocks.append(blocks[pos] as VoxelBlock)
			if not visible_blocks.is_empty():
				var hint_text: String = _format_hint_text(counts)
				visible_blocks[0].set_face_hint(Vector3i(0, 0, -1), hint_text)
				visible_blocks[-1].set_face_hint(Vector3i(0, 0, 1), hint_text)

func _format_hint_text(counts: Array) -> String:
	var total: int = 0
	for count: int in counts:
		total += count
	if counts.is_empty():
		return "0"
	if counts.size() == 1:
		return str(total)
	if counts.size() == 2:
		return "(%d)" % total
	return "[%d]" % total

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

func on_chisel_requested(grid_pos: Vector3i) -> void:
	if not _can_edit_grid() or not is_cell_interactable(grid_pos):
		return
	if is_cell_marked(grid_pos) or is_cell_painted(grid_pos):
		return
	if is_editor_mode:
		_set_editor_target(grid_pos, false)
		return

	var state: Dictionary = voxel_states[grid_pos]
	var previous_state: CellState = int(state.get("cell_state", CellState.UNBROKEN))
	record_move(grid_pos, previous_state)
	if is_target_cell(grid_pos):
		mark_cell(grid_pos)
		if not is_tutorial:
			_handle_mistake()
		_play_ui_sound("error")
		block_destroyed.emit(grid_pos, false)
		return

	if not hammer_cell(grid_pos):
		move_history.pop_back()
		return
	combo += 1
	combo_updated.emit(combo)
	_update_ui_state()
	_play_ui_sound("chisel", combo)
	_pulse_combo_label()
	block_destroyed.emit(grid_pos, is_player_action)
	_check_and_auto_clear_lines(grid_pos)

func on_mark_requested(grid_pos: Vector3i) -> void:
	if not _can_edit_grid() or not is_cell_interactable(grid_pos):
		return
	if is_editor_mode:
		_set_editor_target(grid_pos, true)
		return

	var state: Dictionary = voxel_states[grid_pos]
	var previous_state: CellState = int(state.get("cell_state", CellState.UNBROKEN))
	record_move(grid_pos, previous_state)
	match current_mode:
		EditMode.PAINT:
			if not paint_cell(grid_pos):
				move_history.pop_back()
				return
			_play_ui_sound("mark")
		EditMode.MARK:
			if not mark_cell(grid_pos):
				move_history.pop_back()
				return
			_play_ui_sound("mark")
			voxel_marked.emit(grid_pos)
		_:
			move_history.pop_back()
			if not is_tutorial:
				_handle_mistake()
			else:
				_play_ui_sound("error")

func _set_editor_target(grid_pos: Vector3i, should_be_target: bool) -> void:
	var state: Dictionary = voxel_states[grid_pos]
	var previous_state: CellState = int(state.get("cell_state", CellState.UNBROKEN))
	var previous_target: bool = is_target_cell(grid_pos)
	if previous_target == should_be_target and (should_be_target or not is_cell_chiseled(grid_pos)):
		return
	record_move(grid_pos, previous_state, previous_target)
	target_solution[grid_pos] = should_be_target
	state["is_target"] = should_be_target
	_set_canonical_cell_state(grid_pos, CellState.UNBROKEN if should_be_target else CellState.DESTROYED)

func _play_ui_sound(sound_name: String, combo: int = 0) -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if not audio_manager:
		return
	match sound_name:
		"chisel":
			audio_manager.call("play_chisel_sfx", combo)
		"mark":
			audio_manager.call("play_paint_sfx")
		"error":
			audio_manager.call("play_error_sfx")
		"toggle":
			audio_manager.call("play_ui_click_sfx")
		"victory":
			audio_manager.call("play_victory_sfx")

func _pulse_combo_label() -> void:
	if not combo_label:
		return
	combo_label.pivot_offset = combo_label.size / 2.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(combo_label, "scale", Vector2(1.5, 1.5), 0.1)
	tween.tween_property(combo_label, "modulate", Color(1.0, 0.84, 0.0, 1.0), 0.1)
	tween.chain().tween_property(combo_label, "scale", Vector2.ONE, 0.2)
	tween.parallel().tween_property(combo_label, "modulate", Color.WHITE, 0.2)

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

func record_move(pos: Vector3i, previous_state: int, previous_target_override: Variant = null) -> void:
	var previous_target: bool = is_target_cell(pos) if previous_target_override == null else bool(previous_target_override)
	move_history.append({"pos": pos, "state": previous_state, "target": previous_target})
	history_updated.emit(true)
	_update_ui_state()

func undo_last_move() -> void:
	if not _can_edit_grid() or move_history.is_empty():
		return
	var last_move: Variant = move_history.pop_back()
	if last_move is Array:
		for move: Dictionary in last_move:
			_apply_undo_move(move)
	else:
		_apply_undo_move(last_move as Dictionary)
	_update_slicing()
	_update_clues()
	history_updated.emit(not move_history.is_empty())
	_update_ui_state()

func _apply_undo_move(move: Dictionary) -> void:
	var pos: Vector3i = move["pos"]
	if not voxel_states.has(pos):
		return
	var previous_state: CellState = int(move.get("state", CellState.UNBROKEN))
	var previous_target: bool = bool(move.get("target", is_target_cell(pos)))
	target_solution[pos] = previous_target
	var state: Dictionary = voxel_states[pos]
	state["is_target"] = previous_target
	_set_canonical_cell_state(pos, previous_state)

func on_hover_requested(grid_pos: Vector3i, is_hover: bool) -> void:
	if not voxel_states.has(grid_pos) or is_cell_chiseled(grid_pos):
		hovered_pos = Vector3i(-1, -1, -1)
		_update_multimesh()
		return

	if is_hover:
		hovered_pos = grid_pos
	else:
		if hovered_pos == grid_pos:
			hovered_pos = Vector3i(-1, -1, -1)
	_update_multimesh()

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
		if get_node_or_null("/root/AudioManager"): get_node("/root/AudioManager").trigger_haptic_heavy()
	if camera:
		var pivot = camera.get_parent()
		while pivot != null and not pivot.has_method("shake"):
			pivot = pivot.get_parent()
		if pivot and pivot.has_method("shake"):
			pivot.shake(0.3, 0.2)

	if player_hp <= 0:
		is_puzzle_active = false
		input_locked = true
		_update_ui_state()
		game_over.emit()
		print("Game Over! The active game mode owns restart and retry flow.")

func destroy_block(block: VoxelBlock) -> bool:
	if not block or not is_instance_valid(block) or not voxel_states.has(block.grid_position):
		return false
	if not is_puzzle_active or input_locked or is_cell_chiseled(block.grid_position):
		return false
	if not hammer_cell(block.grid_position):
		return false

	var dummy := MeshInstance3D.new()
	dummy.mesh = BoxMesh.new()
	dummy.mesh.size = Vector3(0.98, 0.98, 0.98)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color("#70D6FF")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dummy.material_override = mat
	dummy.position = block.position
	add_child(dummy)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(dummy, "scale", Vector3.ZERO, 0.15)
	tween.tween_callback(dummy.queue_free)

	if is_player_action:
		combo += 1
		combo_updated.emit(combo)
		_update_ui_state()
		_play_ui_sound("chisel", combo)
		_pulse_combo_label()
		_check_and_auto_clear_lines(block.grid_position)
	block_destroyed.emit(block.grid_position, is_player_action)
	return true

func check_puzzle_complete() -> bool:
	if player_hp <= 0:
		return false
	var expected_count: int = grid_size.x * grid_size.y * grid_size.z
	if voxel_states.size() != expected_count or target_solution.size() != expected_count:
		return false
	for x: int in range(grid_size.x):
		for y: int in range(grid_size.y):
			for z: int in range(grid_size.z):
				if not is_cell_correct(Vector3i(x, y, z)):
					return false
	return true

func _check_win_condition() -> void:
	if puzzle_solved_emitted or not is_puzzle_active or not check_puzzle_complete():
		return
	puzzle_solved_emitted = true
	is_puzzle_active = false
	input_locked = true
	_update_ui_state()
	_play_ui_sound("victory")
	print("Puzzle Solved! Revealing model...")
	puzzle_solved.emit()
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

	# Initialize MultiMesh batching
	_setup_multimesh()

	var game_manager := get_node_or_null("/root/GameManager")

	if has_custom_puzzle and not custom_puzzle_data.is_empty():
		puzzle_name = str(custom_puzzle_data.get("name", custom_puzzle_data.get("id", "Puzzle")))
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

	# Trigger Voxel-to-Mesh Transition Shader using MultiMesh properties
	if is_instance_valid(multimesh_unbroken):
		var mat = multimesh_unbroken.multimesh.mesh.surface_get_material(0)
		if mat is StandardMaterial3D:
			# Morph raw voxel block to a detailed material (simulated via shader changes)
			var tween = create_tween()
			tween.tween_property(mat, "albedo_color", Color(2.0, 2.0, 2.0, 1.0), 0.5) # Glow up
			tween.tween_property(mat, "albedo_color", sculpture_color, 1.0) # Settle into sculpture color

# Deal damage to Boss (if in endless gauntlet mode)
	var time_bonus = max(0.0, 60.0 - time_elapsed) * 2.0
	var combo_bonus = combo * 5.0
	var damage = 50.0 + time_bonus + combo_bonus
	boss_hp -= damage
	_update_ui_state()

	if game_manager and game_manager.has_method("add_trophy"):
		game_manager.add_trophy(puzzle_name)

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
	var gauntlet := _find_round_owner()
	if gauntlet and gauntlet.has_method("_on_quit_pressed"):
		gauntlet.call("_on_quit_pressed")
		return
	local_confirm_dialog = get_node_or_null("CanvasLayer/Control/ConfirmDialog") as Control
	if local_confirm_dialog:
		var yes_button := local_confirm_dialog.get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/YesButton") as Button
		var no_button := local_confirm_dialog.get_node_or_null("MarginContainer/VBoxContainer/HBoxContainer/NoButton") as Button
		if yes_button and not yes_button.pressed.is_connected(_confirm_leave):
			yes_button.pressed.connect(_confirm_leave)
		if no_button and not no_button.pressed.is_connected(_dismiss_local_confirm):
			no_button.pressed.connect(_dismiss_local_confirm)
		if not local_confirm_dialog.visibility_changed.is_connected(_on_local_confirm_visibility_changed):
			local_confirm_dialog.visibility_changed.connect(_on_local_confirm_visibility_changed)
		local_confirm_dialog.show()
		return
	_confirm_leave()

func _on_local_confirm_visibility_changed() -> void:
	if local_confirm_dialog:
		set_input_locked(local_confirm_dialog.visible)

func _dismiss_local_confirm() -> void:
	if local_confirm_dialog:
		local_confirm_dialog.hide()

func _find_round_owner() -> Node:
	var current := get_parent()
	while current:
		if current.has_method("_on_quit_pressed") or current.has_method("_on_yes_pressed"):
			return current
		current = current.get_parent()
	return null

func _confirm_leave() -> void:
	var gauntlet := _find_round_owner()
	if gauntlet and gauntlet.has_method("_on_yes_pressed"):
		gauntlet.call("_on_yes_pressed")
		return
	var game_manager := get_node_or_null("/root/GameManager")
	if not game_manager:
		return
	var target_mode: int = GameManagerClass.GameMode.PUZZLE_SELECTION if has_custom_puzzle else GameManagerClass.GameMode.MAIN_MENU
	game_manager.switch_mode(target_mode)


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


func _setup_multimesh() -> void:
	if is_instance_valid(multimesh_unbroken):
		return # Already initialized

	# Outer Frame MultiMesh (Subtle Translucent Glass Bevel)
	multimesh_outline = MultiMeshInstance3D.new()
	var mm_o = MultiMesh.new()
	mm_o.transform_format = MultiMesh.TRANSFORM_3D
	mm_o.mesh = BoxMesh.new()
	mm_o.mesh.size = Vector3(0.90, 0.90, 0.90)
	var mat_o = StandardMaterial3D.new()
	mat_o.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_o.albedo_color = Color(0.75, 0.88, 0.98, 0.35)
	mat_o.roughness = 0.3
	mm_o.mesh.surface_set_material(0, mat_o)
	multimesh_outline.multimesh = mm_o
	add_child(multimesh_outline)

	# Inner Unbroken Translucent Glass Face MultiMesh
	multimesh_unbroken = MultiMeshInstance3D.new()
	var mm_u = MultiMesh.new()
	mm_u.transform_format = MultiMesh.TRANSFORM_3D
	mm_u.mesh = BoxMesh.new()
	mm_u.mesh.size = Vector3(0.98, 0.98, 0.98)
	var mat_u = StandardMaterial3D.new()
	mat_u.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_u.albedo_color = Color(0.85, 0.93, 0.98, 0.70) # Frosted glass pastel blue-white
	mat_u.roughness = 0.25
	mat_u.metallic = 0.05
	mat_u.emission_enabled = true
	mat_u.emission = Color(0.2, 0.45, 0.7, 1.0)
	mat_u.emission_energy_multiplier = 0.35 # Soft internal light source
	mm_u.mesh.surface_set_material(0, mat_u)
	multimesh_unbroken.multimesh = mm_u
	add_child(multimesh_unbroken)

	# Inner Marked Solid Orange MultiMesh
	multimesh_marked = MultiMeshInstance3D.new()
	var mm_m = MultiMesh.new()
	mm_m.transform_format = MultiMesh.TRANSFORM_3D
	mm_m.mesh = BoxMesh.new()
	mm_m.mesh.size = Vector3(0.98, 0.98, 0.98)
	var mat_m = StandardMaterial3D.new()
	mat_m.albedo_color = Color(1.0, 0.45, 0.0, 1.0) # Solid high-intensity glowing warm orange
	mat_m.roughness = 0.3
	mat_m.metallic = 0.0
	mat_m.emission_enabled = true
	mat_m.emission = Color(1.0, 0.35, 0.0, 1.0)
	mat_m.emission_energy_multiplier = 1.0 # High contrast glowing warm orange light
	mm_m.mesh.surface_set_material(0, mat_m)
	multimesh_marked.multimesh = mm_m
	add_child(multimesh_marked)

	# Hover Highlight MultiMesh
	multimesh_highlight = MultiMeshInstance3D.new()
	var mm_h = MultiMesh.new()
	mm_h.transform_format = MultiMesh.TRANSFORM_3D
	mm_h.mesh = BoxMesh.new()
	mm_h.mesh.size = Vector3(0.93, 0.93, 0.93)
	var mat_h = StandardMaterial3D.new()
	mat_h.albedo_color = Color(1.0, 0.7, 0.1, 0.9)
	mat_h.roughness = 0.3
	mat_h.emission_enabled = true
	mat_h.emission = Color(1.0, 0.6, 0.0, 1.0)
	mat_h.emission_energy_multiplier = 0.8
	mm_h.mesh.surface_set_material(0, mat_h)
	multimesh_highlight.multimesh = mm_h
	add_child(multimesh_highlight)

	multimesh_ghost = MultiMeshInstance3D.new()
	var mm_g = MultiMesh.new()
	mm_g.transform_format = MultiMesh.TRANSFORM_3D
	mm_g.mesh = BoxMesh.new()
	mm_g.mesh.size = Vector3(0.8, 0.8, 0.8)
	var mat_g = StandardMaterial3D.new()
	mat_g.albedo_color = Color(0.5, 0.5, 0.5, 0.2) # Ghost layer
	mat_g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_g.roughness = 1.0
	mm_g.mesh.surface_set_material(0, mat_g)
	multimesh_ghost.multimesh = mm_g
	add_child(multimesh_ghost)

func _update_multimesh() -> void:
	if not is_instance_valid(multimesh_unbroken) or not is_instance_valid(multimesh_marked) or not is_instance_valid(multimesh_outline):
		return

	var unbroken_count = 0
	var marked_count = 0
	var total_active = 0

	for pos in voxel_states.keys():
		var state = voxel_states[pos]
		if is_cell_chiseled(pos) or state.get("is_hidden_by_slice", false):
			continue
		total_active += 1
		if is_cell_marked(pos) or state.get("is_painted", false) or (not is_puzzle_active and is_target_cell(pos)):
			marked_count += 1
		else:
			unbroken_count += 1

	multimesh_outline.multimesh.instance_count = total_active if is_puzzle_active else 0
	multimesh_unbroken.multimesh.instance_count = unbroken_count
	multimesh_marked.multimesh.instance_count = marked_count
	multimesh_highlight.multimesh.instance_count = 1 if (hovered_pos != Vector3i(-1, -1, -1) and not is_cell_chiseled(hovered_pos) and is_puzzle_active) else 0

	var o_idx = 0
	var u_idx = 0
	var m_idx = 0
	var offset = -Vector3(grid_size) / 2.0 + Vector3(0.5, 0.5, 0.5)

	for pos in voxel_states.keys():
		var state = voxel_states[pos]
		if is_cell_chiseled(pos) or state.get("is_hidden_by_slice", false):
			continue

		var transform = Transform3D(Basis(), Vector3(pos.x, pos.y, pos.z) + offset)
		if is_puzzle_active:
			multimesh_outline.multimesh.set_instance_transform(o_idx, transform)
			o_idx += 1

		if is_cell_marked(pos) or state.get("is_painted", false) or (not is_puzzle_active and is_target_cell(pos)):
			multimesh_marked.multimesh.set_instance_transform(m_idx, transform)
			m_idx += 1
		else:
			multimesh_unbroken.multimesh.set_instance_transform(u_idx, transform)
			u_idx += 1

	if hovered_pos != Vector3i(-1, -1, -1) and not is_cell_chiseled(hovered_pos) and is_puzzle_active:
		multimesh_highlight.multimesh.set_instance_transform(0, Transform3D(Basis(), Vector3(hovered_pos.x, hovered_pos.y, hovered_pos.z) + offset))


func _check_and_auto_clear_lines(last_pos: Vector3i) -> void:
	return # Automatically exploding tiles feature disabled per user request

	# Check X axis
	var x_targets = 0
	var x_found = 0
	var x_unbroken = 0
	for x in range(grid_size.x):
		var pos = Vector3i(x, last_pos.y, last_pos.z)
		if voxel_states.has(pos):
			var state = voxel_states[pos]
			if state.get("is_target", false): x_targets += 1
			if state.get("is_chiseled", false) or state.get("is_marked", false):
				if state.get("is_target", false): x_found += 1
			if not state.get("is_chiseled", false): x_unbroken += 1

	if x_targets > 0 and x_found == x_targets and x_unbroken > x_targets:
		for x in range(grid_size.x):
			var pos = Vector3i(x, last_pos.y, last_pos.z)
			if voxel_states.has(pos) and not voxel_states[pos].get("is_chiseled", false) and not voxel_states[pos].get("is_target", false):
				on_chisel_requested(pos)

	# Check Y axis
	var y_targets = 0
	var y_found = 0
	var y_unbroken = 0
	for y in range(grid_size.y):
		var pos = Vector3i(last_pos.x, y, last_pos.z)
		if voxel_states.has(pos):
			var state = voxel_states[pos]
			if state.get("is_target", false): y_targets += 1
			if state.get("is_chiseled", false) or state.get("is_marked", false):
				if state.get("is_target", false): y_found += 1
			if not state.get("is_chiseled", false): y_unbroken += 1

	if y_targets > 0 and y_found == y_targets and y_unbroken > y_targets:
		for y in range(grid_size.y):
			var pos = Vector3i(last_pos.x, y, last_pos.z)
			if voxel_states.has(pos) and not voxel_states[pos].get("is_chiseled", false) and not voxel_states[pos].get("is_target", false):
				on_chisel_requested(pos)

	# Check Z axis
	var z_targets = 0
	var z_found = 0
	var z_unbroken = 0
	for z in range(grid_size.z):
		var pos = Vector3i(last_pos.x, last_pos.y, z)
		if voxel_states.has(pos):
			var state = voxel_states[pos]
			if state.get("is_target", false): z_targets += 1
			if state.get("is_chiseled", false) or state.get("is_marked", false):
				if state.get("is_target", false): z_found += 1
			if not state.get("is_chiseled", false): z_unbroken += 1

	if z_targets > 0 and z_found == z_targets and z_unbroken > z_targets:
		for z in range(grid_size.z):
			var pos = Vector3i(last_pos.x, last_pos.y, z)
			if voxel_states.has(pos) and not voxel_states[pos].get("is_chiseled", false) and not voxel_states[pos].get("is_target", false):
				on_chisel_requested(pos)
