extends Node3D

class_name GridManager

const VoxelLogicSolver = preload("res://scripts/VoxelLogicSolver.gd")
const PuzzleDataValidator = preload("res://scripts/PuzzleDataValidator.gd")
const RunHistoryServiceClass = preload("res://scripts/RunHistoryService.gd")

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
var victory_preview: Dictionary = {}

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
	if is_inside_tree() and has_node("CanvasLayer") and (input_locked or not is_puzzle_active):
		return false
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
	if is_inside_tree() and has_node("CanvasLayer") and (input_locked or not is_puzzle_active):
		return false
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
	if is_inside_tree() and has_node("CanvasLayer") and (input_locked or not is_puzzle_active):
		return false
	if not voxel_states.has(pos):
		return false
	var state: Dictionary = voxel_states[pos]
	if state.get("is_hidden_by_slice", false) or is_cell_chiseled(pos) or is_cell_marked(pos):
		return false
	# This is the primitive that writes the state, so the "a kept voxel is never
	# destroyed" rule belongs here rather than only in the click handler. Without
	# it, any future caller that reached this function directly could destroy a
	# target with no mistake charged and no undo entry, leaving the round
	# permanently unwinnable while looking like a perfect run.
	if is_target_cell(pos):
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
@onready var reset_view_btn: Button = null
@onready var export_btn: Button = null

@onready var round_label: Label = null
@onready var hp_label: Label = null
@onready var combo_label: Label = null
@onready var timer_label: Label = null
@onready var boss_name_label: Label = null
@onready var boss_hp_bar: ProgressBar = null
@onready var leave_btn: Button = null
@onready var gameplay_margin: MarginContainer = null

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
var standalone_game_over: Control = null
var standalone_game_over_message: Label = null
var standalone_game_over_title: Label = null

func _ready() -> void:
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
	gameplay_margin = get_node_or_null("CanvasLayer/Control/MarginContainer") as MarginContainer
	if gameplay_margin:
		get_viewport().size_changed.connect(_apply_safe_area_layout)
		call_deferred("_apply_safe_area_layout")
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

	_setup_standalone_game_over()
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
	reset_view_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/ResetViewButton")
	if hint_btn and not hint_btn.pressed.is_connected(_on_hint_pressed):
		hint_btn.pressed.connect(_on_hint_pressed)
	if reset_view_btn and not reset_view_btn.pressed.is_connected(_on_reset_view_pressed):
		reset_view_btn.pressed.connect(_on_reset_view_pressed)
	var hint_mechanic := get_node_or_null("CooldownHintMechanic") as CooldownHintMechanic
	if hint_mechanic:
		if not hint_mechanic.hint_ready.is_connected(_on_hint_ready):
			hint_mechanic.hint_ready.connect(_on_hint_ready)
		if not hint_mechanic.cooldown_updated.is_connected(_on_hint_cooldown):
			hint_mechanic.cooldown_updated.connect(_on_hint_cooldown)
	if export_btn and not export_btn.pressed.is_connected(_export_puzzle):
		export_btn.pressed.connect(_export_puzzle)
	_update_ui_state()
	# Custom puzzles return early from start_level before the input nodes are
	# connected. Re-run the semantic tutorial hookup now that camera/touch and
	# slice signals exist, so onboarding cannot silently skip its first step.
	if is_tutorial:
		_setup_tutorial(custom_puzzle_data)

func _setup_standalone_game_over() -> void:
	if standalone_game_over != null:
		return
	var canvas_layer: CanvasLayer = get_node_or_null("CanvasLayer") as CanvasLayer
	if canvas_layer == null:
		return
	standalone_game_over = Control.new()
	standalone_game_over.name = "StandaloneGameOver"
	standalone_game_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	standalone_game_over.mouse_filter = Control.MOUSE_FILTER_STOP
	standalone_game_over.z_index = 50
	standalone_game_over.visible = false
	canvas_layer.add_child(standalone_game_over)

	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.03, 0.05, 0.09, 0.78)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	standalone_game_over.add_child(scrim)

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -220.0
	card.offset_right = 220.0
	card.offset_top = -150.0
	card.offset_bottom = 150.0
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.96, 0.97, 0.99, 1.0)
	card_style.corner_radius_top_left = 18
	card_style.corner_radius_top_right = 18
	card_style.corner_radius_bottom_left = 18
	card_style.corner_radius_bottom_right = 18
	card.add_theme_stylebox_override("panel", card_style)
	standalone_game_over.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	card.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)
	var title := Label.new()
	title.text = "PUZZLE FAILED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.12, 0.2, 0.32, 1.0))
	content.add_child(title)
	standalone_game_over_title = title
	standalone_game_over_message = Label.new()
	standalone_game_over_message.text = "You can retry this puzzle or return to the compendium."
	standalone_game_over_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	standalone_game_over_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	standalone_game_over_message.add_theme_font_size_override("font_size", 16)
	standalone_game_over_message.add_theme_color_override("font_color", Color(0.25, 0.3, 0.38, 1.0))
	content.add_child(standalone_game_over_message)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	var retry_button := Button.new()
	retry_button.name = "RetryButton"
	retry_button.text = "Retry"
	retry_button.custom_minimum_size = Vector2(140, 48)
	retry_button.pressed.connect(_retry_standalone)
	actions.add_child(retry_button)
	var leave_button := Button.new()
	leave_button.name = "LeaveButton"
	leave_button.text = "Leave"
	leave_button.custom_minimum_size = Vector2(140, 48)
	leave_button.pressed.connect(_on_leave_requested)
	actions.add_child(leave_button)


func _safe_focus(control: Control) -> void:
	if is_inside_tree() and is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree():
		control.grab_focus()


func _show_standalone_game_over() -> void:
	if _find_round_owner() != null:
		return
	if standalone_game_over:
		standalone_game_over.show()
		if standalone_game_over_title:
			standalone_game_over_title.text = "PUZZLE FAILED"
		standalone_game_over_message.text = "No lives remaining. Retry this puzzle or return to the compendium."
		var retry_button: Button = standalone_game_over.find_child("RetryButton", true, false) as Button
		if retry_button:
			retry_button.text = "Retry"
			retry_button.show()
			if retry_button.pressed.is_connected(_confirm_leave):
				retry_button.pressed.disconnect(_confirm_leave)
			if not retry_button.pressed.is_connected(_retry_standalone):
				retry_button.pressed.connect(_retry_standalone)
			call_deferred("_safe_focus", retry_button)


func _show_load_error(message: String) -> void:
	if standalone_game_over == null:
		return
	standalone_game_over.show()
	if standalone_game_over_title:
		standalone_game_over_title.text = "PUZZLE UNAVAILABLE"
	if standalone_game_over_message:
		standalone_game_over_message.text = message
	var retry_button: Button = standalone_game_over.find_child("RetryButton", true, false) as Button
	if retry_button:
		retry_button.text = "Return to Menu"
		if retry_button.pressed.is_connected(_retry_standalone):
			retry_button.pressed.disconnect(_retry_standalone)
		if not retry_button.pressed.is_connected(_confirm_leave):
			retry_button.pressed.connect(_confirm_leave)
		call_deferred("_safe_focus", retry_button)


func _hide_standalone_game_over() -> void:
	if standalone_game_over:
		standalone_game_over.hide()


func _retry_standalone() -> void:
	var retry_button: Button = standalone_game_over.find_child("RetryButton", true, false) as Button if standalone_game_over else null
	if retry_button:
		retry_button.text = "Retry"
		if retry_button.pressed.is_connected(_confirm_leave):
			retry_button.pressed.disconnect(_confirm_leave)
		if not retry_button.pressed.is_connected(_retry_standalone):
			retry_button.pressed.connect(_retry_standalone)
	_hide_standalone_game_over()
	start_level()


func _on_reset_view_pressed() -> void:
	var pivot: Node = camera.get_parent() if camera else null
	while pivot != null and not pivot.has_method("reset_view"):
		pivot = pivot.get_parent()
	if pivot and pivot.has_method("reset_view"):
		# Honour the reduced-motion setting here too: the camera shake already
		# did, so an animated reset was the inconsistent case.
		pivot.call("reset_view", 0.0 if _is_reduced_motion_enabled() else 0.22)


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
	var canonical_puzzle: Dictionary = {}
	var canonical_solution: Dictionary = {}
	# Never trust a caller-supplied `runtime_validated`/`solvable` flag for
	# player-facing content. Strict mode proves that the stored clues have one
	# solution matching the target before an interactive grid is created.
	var analysis: Dictionary = PuzzleDataValidator.analyze_puzzle(puzzle_data, true, false)
	if not bool(analysis.get("ok", false)):
		push_error("Rejected invalid custom puzzle '%s': %s" % [puzzle_data.get("id", puzzle_data.get("name", "unknown")), str(analysis.get("errors", []))])
		has_custom_puzzle = false
		custom_puzzle_data = {}
		is_puzzle_active = false
		input_locked = true
		_show_load_error("This puzzle did not pass validation. Return to the menu and choose another sculpture.")
		# start_level() returns before its own UI refresh, so the toolbar and HUD
		# would otherwise keep the pre-round enabled state behind the error card.
		_update_ui_state()
		return
	canonical_puzzle = (analysis.get("puzzle", {}) as Dictionary).duplicate(true)
	canonical_solution = analysis.get("solution", {}) as Dictionary

	custom_puzzle_data = canonical_puzzle
	var dims_array: Array = custom_puzzle_data.get("dims", custom_puzzle_data.get("grid_size", [3, 3, 3]))
	if dims_array.size() != 3:
		push_error("Custom puzzle has invalid dimensions")
		is_puzzle_active = false
		input_locked = true
		_show_load_error("This puzzle has invalid dimensions and cannot be played safely.")
		_update_ui_state()
		return
	grid_size = Vector3i(int(dims_array[0]), int(dims_array[1]), int(dims_array[2]))
	slice_max = grid_size - Vector3i.ONE
	target_solution.clear()
	for coordinate: Vector3i in canonical_solution.keys():
		target_solution[coordinate] = bool(canonical_solution[coordinate])
	for z: int in range(grid_size.z):
		for y: int in range(grid_size.y):
			for x: int in range(grid_size.x):
				var coordinate := Vector3i(x, y, z)
				if not target_solution.has(coordinate):
					target_solution[coordinate] = false

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
	if not tutorial_manager.step_advanced.is_connected(_on_tutorial_step_advanced):
		tutorial_manager.step_advanced.connect(_on_tutorial_step_advanced)


func _on_tutorial_step_advanced(step_index: int, _instruction: String) -> void:
	if step_index == TutorialManager.Step.LAYER_SLICING and slice_controls:
		slice_controls.show()
		if slice_slider_y and slice_slider_y.is_inside_tree():
			slice_slider_y.grab_focus()


func _on_tutorial_layer_slider_changed(value: float) -> void:
	if is_instance_valid(tutorial_manager):
		if tutorial_manager.current_step == TutorialManager.Step.LAYER_SLICING and slice_controls:
			slice_controls.show()
		tutorial_manager.on_layer_slider_changed("Y", int(value))


func start_level() -> void:
	_hide_standalone_game_over()
	is_puzzle_active = true
	puzzle_solved_emitted = false
	input_locked = false
	start_time = Time.get_ticks_msec()
	mistakes = 0
	combo = 0
	player_hp = 3
	move_history.clear()
	victory_preview.clear()

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
	reset_view_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/ResetViewButton")
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
	if reset_view_btn and not reset_view_btn.pressed.is_connected(_on_reset_view_pressed):
		reset_view_btn.pressed.connect(_on_reset_view_pressed)

	_update_ui_state()

	_fit_camera_to_grid()

func _apply_safe_area_layout() -> void:
	if not is_inside_tree() or gameplay_margin == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var insets: Vector4 = _get_safe_area_insets(viewport_size)
	var display_size: Vector2 = _get_display_size()
	var ui_scale: float = _get_ui_scale(viewport_size, display_size)
	var compact: bool = display_size.x < 600.0 or display_size.y < 500.0
	var padding: float = (10.0 if compact else 18.0) * ui_scale
	gameplay_margin.offset_left = insets.x + padding
	gameplay_margin.offset_top = insets.y + padding
	gameplay_margin.offset_right = -(insets.z + padding)
	gameplay_margin.offset_bottom = -(insets.w + padding)
	gameplay_margin.add_theme_constant_override("margin_left", int((4 if compact else 8) * ui_scale))
	gameplay_margin.add_theme_constant_override("margin_top", int((4 if compact else 8) * ui_scale))
	gameplay_margin.add_theme_constant_override("margin_right", int((4 if compact else 8) * ui_scale))
	gameplay_margin.add_theme_constant_override("margin_bottom", int((4 if compact else 8) * ui_scale))
	var toolbar: GridContainer = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer") as GridContainer
	if toolbar:
		var toolbar_parent: Control = toolbar.get_parent() as Control
		if toolbar_parent:
			toolbar_parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		toolbar.columns = 5 if display_size.x >= 1000.0 else 4 if display_size.x >= 800.0 else 3 if display_size.x >= 600.0 else 2
		for child in toolbar.get_children():
			if child is Button:
				var toolbar_button := child as Button
				var touch_width: float = maxf(toolbar_button.custom_minimum_size.x, 64.0 * ui_scale)
				var touch_height: float = maxf(toolbar_button.custom_minimum_size.y, 44.0 * ui_scale)
				toolbar_button.custom_minimum_size = Vector2(touch_width, touch_height)
				toolbar_button.add_theme_font_size_override("font_size", int(16 * ui_scale))
	var slice_controls: Control = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/SliceControls") as Control
	if slice_controls:
		for child in slice_controls.get_children():
			if child is HSlider:
				(child as HSlider).custom_minimum_size.y = maxf((child as HSlider).custom_minimum_size.y, 44.0 * ui_scale)


func _get_display_size() -> Vector2:
	var window_size := Vector2(DisplayServer.window_get_size())
	return window_size if window_size.x > 0.0 and window_size.y > 0.0 else get_viewport().get_visible_rect().size


func _get_ui_scale(viewport_size: Vector2, display_size: Vector2) -> float:
	if display_size.x <= 0.0 or display_size.y <= 0.0:
		return 1.0
	return clampf(maxf(viewport_size.x / display_size.x, viewport_size.y / display_size.y), 1.0, 4.0)


func _is_reduced_motion_enabled() -> bool:
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("get_settings"):
		return false
	var settings: Dictionary = save_manager.call("get_settings")
	return bool(settings.get("reduced_motion", false))


func _get_safe_area_insets(viewport_size: Vector2) -> Vector4:
	var minimum_insets: Vector4 = Vector4(8.0, 8.0, 8.0, 8.0)
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
			# Escape must dismiss an open dialog rather than re-open it. The
			# gauntlet already did this; the standalone flow called show() on an
			# already-visible panel, so back did nothing and the player had to
			# find the No button.
			if local_confirm_dialog != null and local_confirm_dialog.visible:
				_dismiss_local_confirm()
				get_viewport().set_input_as_handled()
			else:
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
	var puzzle_data: Dictionary = {}
	var fallback_path: String = "res://data/puzzles/test_2x2.json" if base_grid_size == 2 else "res://data/puzzles/tutorial_star.json"
	if FileAccess.file_exists(fallback_path):
		var file: FileAccess = FileAccess.open(fallback_path, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				puzzle_data = parsed as Dictionary
	if puzzle_data.is_empty():
		var puzzle_manager: Node = get_node_or_null("/root/PuzzleManager")
		if puzzle_manager and puzzle_manager.has_method("get_fallback_puzzle"):
			var selected: Variant = puzzle_manager.call("get_fallback_puzzle")
			if selected is Dictionary:
				puzzle_data = selected as Dictionary
	if puzzle_data.is_empty():
		push_error("[GridManager] No canonical puzzle data is available; refusing to invent a solution")
		return
	var analysis: Dictionary = PuzzleDataValidator.analyze_puzzle(puzzle_data, true, true)
	if not bool(analysis.get("ok", false)):
		push_error("[GridManager] Canonical fallback puzzle failed validation: %s" % str(analysis.get("errors", [])))
		return
	var canonical: Dictionary = analysis.get("puzzle", {}) as Dictionary
	var dimensions: Array = canonical.get("dims", canonical.get("grid_size", []))
	if dimensions.size() == 3:
		grid_size = Vector3i(int(dimensions[0]), int(dimensions[1]), int(dimensions[2]))
		slice_max = grid_size - Vector3i.ONE
	for coordinate: Variant in canonical.get("target_voxels", []):
		if coordinate is Array and coordinate.size() == 3:
			target_solution[Vector3i(int(coordinate[0]), int(coordinate[1]), int(coordinate[2]))] = true
	for z: int in range(grid_size.z):
		for y: int in range(grid_size.y):
			for x: int in range(grid_size.x):
				var coordinate := Vector3i(x, y, z)
				if not target_solution.has(coordinate):
					target_solution[coordinate] = false


func _build_grid() -> void:
	# MultiMesh owns the visible voxel bodies and interaction data stays in
	# dictionaries. Do not instantiate the full Block.tscn (StaticBody3D,
	# mesh, collision, and particles) for every cell: at 5x5x5 that creates a
	# large, mostly-hidden scene tree on mobile. Clue hosts are intentionally
	# bare VoxelBlock nodes and create only the Label3D/Sprite3D faces they use.
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			for z in range(grid_size.z):
				var pos := Vector3i(x, y, z)
				voxel_states[pos] = {
					"is_target": target_solution.get(pos, false),
					"cell_state": CellState.UNBROKEN,
					"is_painted": false,
					"is_hidden_by_slice": false
				}
				var block := VoxelBlock.new()
				block.name = "ClueHost_%d_%d_%d" % [x, y, z]
				block.lightweight_mode = true
				add_child(block)
				block.set_grid_position(pos)
				block.set_meta("grid_pos", pos)
				block.position = Vector3(x, y, z) - Vector3(grid_size) / 2.0 + Vector3(0.5, 0.5, 0.5)
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
	# Keep group order visible. Reducing [1,2] and [2,1] to the same total makes
	# the displayed puzzle weaker than the canonical validator's constraint.
	if counts.is_empty():
		return "0"
	var parts: Array[String] = []
	for count: int in counts:
		parts.append(str(maxi(0, count)))
	return "·".join(parts)

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
		# A marked cell stays tappable on purpose, so a hammer tap on one used
		# to die here with no sound, no flash and no mistake - indistinguishable
		# from a dropped input. Say something.
		_play_ui_sound("error")
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
	if not combo_label or _is_reduced_motion_enabled():
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
	# Combo has to travel with the move. It is the trigger for the combo-heal
	# mistake refund and it feeds the score bonus, so an undo that restored the
	# cells but not the combo let a player re-chisel the same voxels to launder
	# mistakes and inflate the run score without learning anything.
	move_history.append({"pos": pos, "state": previous_state, "target": previous_target, "combo": combo})
	history_updated.emit(true)
	_update_ui_state()

func undo_last_move() -> void:
	if not _can_edit_grid() or move_history.is_empty():
		return
	var last_move: Variant = move_history.pop_back()
	if last_move is Array:
		var batch: Array = last_move as Array
		for move: Dictionary in batch:
			_apply_undo_move(move)
		# A chained batch is one player action: restore the combo from the first
		# recorded move, which is the state before any of them were applied.
		if not batch.is_empty():
			_restore_combo((batch[0] as Dictionary).get("combo", combo))
	else:
		var single: Dictionary = last_move as Dictionary
		_apply_undo_move(single)
		_restore_combo(single.get("combo", combo))
	_update_slicing()
	_update_clues()
	history_updated.emit(not move_history.is_empty())
	_update_ui_state()

func _restore_combo(restored_combo: Variant) -> void:
	var next_combo: int = maxi(0, int(restored_combo))
	if next_combo == combo:
		return
	combo = next_combo
	if combo_label:
		combo_label.text = "Combo: x%d" % combo
	# Re-emitting is safe: ComboHealMechanic only acts on an exact multiple of
	# its threshold, so restoring to a non-multiple cannot grant a second heal.
	combo_updated.emit(combo)

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
		_update_hover_multimesh()
		return

	if is_hover:
		hovered_pos = grid_pos
	else:
		if hovered_pos == grid_pos:
			hovered_pos = Vector3i(-1, -1, -1)
	_update_hover_multimesh()

func _handle_mistake() -> void:
	mistakes += 1
	combo = 0
	player_hp -= 1
	_update_ui_state()
	emit_signal("mistake_made", mistakes)

	if hp_label and not _is_reduced_motion_enabled():
		# Visual juice for player taking damage
		hp_label.pivot_offset = hp_label.size / 2
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(hp_label, "modulate", Color(1, 0, 0, 1), 0.1)
		tween.tween_property(hp_label, "scale", Vector2(1.5, 1.5), 0.1)
		tween.chain().tween_property(hp_label, "modulate", Color(1, 1, 1, 1), 0.2)
		tween.parallel().tween_property(hp_label, "scale", Vector2(1, 1), 0.2)

	if camera and not _is_reduced_motion_enabled():
		var pivot = camera.get_parent()
		while pivot != null and not pivot.has_method("shake"):
			pivot = pivot.get_parent()
		if pivot and pivot.has_method("shake"):
			pivot.shake(0.3, 0.2)

	if player_hp <= 0:
		is_puzzle_active = false
		input_locked = true
		_update_ui_state()
		_show_standalone_game_over()
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

	# Smooth in-place wave scale transition. Bare clue hosts intentionally skip
	# this cosmetic path; reduced-motion users get the same readable reveal
	# without a screen-wide animation storm.
	if not _is_reduced_motion_enabled():
		for pos in blocks.keys():
			var block = blocks[pos]
			if block.current_state != block.BlockState.DESTROYED and block.current_state != block.BlockState.HIDDEN_BY_SLICE and not block.lightweight_mode:
				var delay = float(pos.x + pos.y + pos.z) * 0.05
				var tween = create_tween()
				tween.tween_interval(delay)
				tween.tween_property(block, "scale", Vector3(1.2, 1.2, 1.2), 0.15).set_trans(Tween.TRANS_SINE)
				tween.tween_property(block, "scale", Vector3(1.0, 1.0, 1.0), 0.15).set_trans(Tween.TRANS_SINE)

	# Start camera orbit
	if camera and not _is_reduced_motion_enabled():
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

	# Color the final sculpture. Clue hosts are lightweight VoxelBlock nodes and
	# have no per-block material, so the visible transition is driven by the
	# shared MultiMesh material below instead of a per-cell albedo write.
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
	var round_owner: Node = _find_round_owner()
	var preview: Dictionary = victory_preview.duplicate(true)
	var elapsed: float = maxf(0.0, time_elapsed)
	var par_time: float = maxf(1.0, float(preview.get("par_time", custom_puzzle_data.get("par_time_seconds", 120.0) if custom_puzzle_data is Dictionary else 120.0)))
	var result_mistakes: int = maxi(0, int(float(preview.get("mistakes", mistakes))))
	var result_time: float = maxf(0.0, float(preview.get("clear_time", elapsed)))
	var stars_earned: int = 3 if result_mistakes == 0 and result_time <= par_time else 2 if result_mistakes <= 1 and result_time <= par_time * 1.5 else 1
	var result_score: int = maxi(0, int(float(preview.get("score", 0))))
	var result_round: int = maxi(1, int(float(preview.get("depth", current_floor))))
	var result_streak: int = maxi(0, int(float(preview.get("streak", combo))))
	var result_reserve: float = maxf(0.0, float(preview.get("banked_time", 0.0)))
	var seed_value: int = 0
	var difficulty: String = "endless"
	var daily_state: bool = false
	var puzzle_id: String = str(custom_puzzle_data.get("id", "")) if custom_puzzle_data is Dictionary else ""
	if round_owner != null:
		seed_value = maxi(0, int(float(round_owner.get("run_seed"))))
		daily_state = bool(round_owner.get("is_daily_challenge"))
		if round_owner.has_method("get_victory_context"):
			var owner_context: Variant = round_owner.call("get_victory_context")
			if owner_context is Dictionary:
				difficulty = str((owner_context as Dictionary).get("difficulty", difficulty))
	if preview.is_empty():
		# Standalone/tutorial results have no Gauntlet authority. Keep their
		# compact, deterministic score formula local to this presentation path.
		result_score = maxi(0, 10000 - int(result_time * 10.0) - result_mistakes * 500)
		difficulty = "practice"
	var title_prefix: String = "Round %d  •  " % result_round if round_owner != null else ""
	var level_title: String = title_prefix + puzzle_name if not puzzle_name.is_empty() else title_prefix + "Puzzle complete"
	var result_data: Dictionary = {
		"current_level_string": level_title,
		"time_seconds": result_time,
		"par_time_seconds": par_time,
		"raw_score": result_score,
		"score": result_score,
		"stars_earned": stars_earned,
		"round": result_round,
		"depth": result_round,
		"seed": seed_value,
		"streak": result_streak,
		"mistakes": result_mistakes,
		"banked_time": result_reserve,
		"difficulty": difficulty,
		"is_daily": daily_state,
		"puzzle_id": puzzle_id,
	}

	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager and round_owner == null and has_custom_puzzle and not custom_puzzle_data.is_empty() and not puzzle_id.is_empty():
		# Gauntlet entries are custom puzzles too, but they must never inflate
		# Compendium completion merely by being part of a run.
		save_manager.call("record_puzzle_completion", puzzle_id, stars_earned, result_time)
		if save_manager.has_method("record_achievement_event"):
			save_manager.call("record_achievement_event", {
				"type": "compendium_puzzle_cleared",
				"event_id": "compendium:%s" % puzzle_id,
				"puzzle_id": puzzle_id,
			})
			var completion: Dictionary = save_manager.call("get_completion")
			if not completion.is_empty():
				save_manager.call("record_achievement_event", {
					"type": "compendium_progress",
					"event_id": "compendium-progress:%d" % completion.size(),
					"completed_count": completion.size(),
				})
	if save_manager and save_manager.has_method("get_run_aggregates"):
		var aggregates: Dictionary = save_manager.call("get_run_aggregates")
		result_data["best_depth"] = int(aggregates.get("best_depth", 0))
		result_data["best_score"] = int(aggregates.get("best_score", 0))
	if seed_value > 0:
		var share_service: RefCounted = RunHistoryServiceClass.new()
		# These versions are part of the share token's checksummed identity, so
		# they must come from the canonical constants instead of literals.
		var share_ruleset_version: int = int(GameManagerClass.DAILY_RULESET_VERSION)
		var share_catalog_version: int = int(GameManagerClass.DAILY_CATALOG_VERSION)
		var share_puzzle_manager: Node = get_node_or_null("/root/PuzzleManager")
		if share_puzzle_manager != null and share_puzzle_manager.has_method("get_catalog_version"):
			share_catalog_version = int(share_puzzle_manager.call("get_catalog_version"))
		var share_result: Dictionary = share_service.call(
			"encode_share_token",
			seed_value,
			difficulty if difficulty in ["easy", "medium", "hard", "endless"] else "endless",
			share_ruleset_version,
			share_catalog_version
		)
		if bool(share_result.get("success", false)):
			result_data["share_code"] = str(share_result.get("token", ""))

	var victory_scene: Control = preload("res://scenes/victory_screen.tscn").instantiate() as Control
	victory_scene.z_index = 1000
	var result_context: String = "gauntlet" if round_owner != null else "tutorial" if is_tutorial else "compendium" if has_custom_puzzle else "standalone"
	victory_scene.set("result_context", result_context)
	var canvas_layer: CanvasLayer = get_node_or_null("CanvasLayer") as CanvasLayer
	if canvas_layer == null:
		victory_scene.queue_free()
		return
	# A child puzzle CanvasLayer otherwise renders below EscapeGauntlet's HUD
	# layer (10), especially during terminal/reveal transitions.
	canvas_layer.layer = maxi(canvas_layer.layer, 20)
	canvas_layer.add_child(victory_scene)
	victory_scene.call("initialize", result_data)
	victory_scene.start_next_nonogram_requested.connect(_on_next_level_requested.bind(victory_scene))
	victory_scene.leave_requested.connect(_on_leave_requested)
	victory_scene.replay_requested.connect(_on_victory_replay_requested)
	victory_scene.new_run_requested.connect(_on_victory_new_run_requested)


func _on_victory_replay_requested() -> void:
	var gauntlet: Node = _find_round_owner()
	if gauntlet != null and gauntlet.has_method("retry_victory_seed"):
		gauntlet.call("retry_victory_seed")
		return
	_remove_victory_overlays()
	start_level()


func _on_victory_new_run_requested() -> void:
	var gauntlet: Node = _find_round_owner()
	if gauntlet != null and gauntlet.has_method("start_new_victory_run"):
		gauntlet.call("start_new_victory_run")
		return
	_remove_victory_overlays()
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("begin_run"):
		game_manager.call("begin_run", "endless")


func _remove_victory_overlays() -> void:
	for child: Node in get_children():
		if child.name == "CanvasLayer":
			for overlay: Node in (child as CanvasLayer).get_children():
				if overlay.name == "VictoryScreen" and is_instance_valid(overlay):
					overlay.queue_free()

func _on_leave_requested() -> void:
	var gauntlet := _find_round_owner()
	if gauntlet and gauntlet.has_method("_on_quit_pressed"):
		gauntlet.call("_on_quit_pressed")
		return
	local_confirm_dialog = get_node_or_null("CanvasLayer/Control/ConfirmDialog") as Control
	if local_confirm_dialog:
		var yes_button: Button = local_confirm_dialog.find_child("YesButton", true, false) as Button
		var no_button: Button = local_confirm_dialog.find_child("NoButton", true, false) as Button
		if yes_button and not yes_button.pressed.is_connected(_confirm_leave):
			yes_button.pressed.connect(_confirm_leave)
		if no_button and not no_button.pressed.is_connected(_dismiss_local_confirm):
			no_button.pressed.connect(_dismiss_local_confirm)
		if not local_confirm_dialog.visibility_changed.is_connected(_on_local_confirm_visibility_changed):
			local_confirm_dialog.visibility_changed.connect(_on_local_confirm_visibility_changed)
		local_confirm_dialog.z_index = 120
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

	# A gauntlet owns the transition after a custom puzzle. Returning to the
	# compendium here races the gauntlet's victory flow and makes Continue exit
	# the run before the next puzzle can load.
	var gauntlet: Node = _find_round_owner()
	if gauntlet != null:
		return

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

func _update_hover_multimesh() -> void:
	if not is_instance_valid(multimesh_highlight):
		return
	var has_hover: bool = hovered_pos != Vector3i(-1, -1, -1) and voxel_states.has(hovered_pos) and not is_cell_chiseled(hovered_pos) and is_puzzle_active
	multimesh_highlight.multimesh.instance_count = 1 if has_hover else 0
	if has_hover:
		var offset: Vector3 = -Vector3(grid_size) / 2.0 + Vector3(0.5, 0.5, 0.5)
		multimesh_highlight.multimesh.set_instance_transform(0, Transform3D(Basis(), Vector3(hovered_pos.x, hovered_pos.y, hovered_pos.z) + offset))


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
