extends Node3D

class_name GridManager

@export var grid_size: Vector3i = Vector3i(5, 5, 5)
@export var block_scene: PackedScene = preload("res://scenes/Block.tscn")
@export var camera: Camera3D

# Internal storage
var blocks: Dictionary = {}
var target_solution: Dictionary = {}

var slice_max: Vector3i
var move_history: Array = []

@onready var labels_container: Node3D = $LabelsContainer

signal puzzle_solved
signal mistake_made(total_mistakes)
signal combo_updated(current_combo)
signal history_updated(can_undo)
signal game_over
signal floor_cleared
signal voxel_destroyed(pos: Vector3i, is_player_action: bool)

var mistakes: int = 0
var combo: int = 0
var player_hp: int = 3
var boss_hp: float = 100.0
var max_boss_hp: float = 100.0
var current_floor: int = 1
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
@onready var slice_toggle_btn: Button = null
@onready var undo_btn: Button = null

@onready var round_label: Label = null
@onready var hp_label: Label = null
@onready var combo_label: Label = null
@onready var timer_label: Label = null
@onready var boss_name_label: Label = null
@onready var boss_hp_bar: ProgressBar = null

enum EditMode { DESTROY, MARK }
var current_mode: EditMode = EditMode.DESTROY

var hovered_block: PicrossBlock = null

func _ready() -> void:
	# Find UI elements
	slice_controls = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/SliceControls")
	if slice_controls:
		slice_slider_x = slice_controls.get_node_or_null("SliderX")
		slice_slider_y = slice_controls.get_node_or_null("SliderY")
		slice_slider_z = slice_controls.get_node_or_null("SliderZ")

	chisel_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/ChiselButton")
	mark_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/MarkButton")
	slice_toggle_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/SliceToggleButton")
	undo_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/UndoButton")

	var top_info = get_node_or_null("CanvasLayer/Control/MarginContainer/TopInfoBar/HBoxContainer")
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
	if mark_btn and not mark_btn.pressed.is_connected(_on_mark_mode_selected):
		mark_btn.pressed.connect(_on_mark_mode_selected)
	if slice_toggle_btn and not slice_toggle_btn.pressed.is_connected(_on_slice_toggle_pressed):
		slice_toggle_btn.pressed.connect(_on_slice_toggle_pressed)
	if undo_btn and not undo_btn.pressed.is_connected(undo_last_move):
		undo_btn.pressed.connect(undo_last_move)

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

	_generate_solution()
	_build_grid()
	_update_slicing()

	_update_clues()

	# Dynamically set max_zoom based on grid size and adjust camera
	if camera:
		var max_dim = max(grid_size.x, max(grid_size.y, grid_size.z))
		var target_zoom = float(max_dim) * 2.5
		# We assume the parent is CameraPivot, which handles max_zoom
		var pivot = camera.get_parent()
		if pivot and "max_zoom" in pivot:
			pivot.max_zoom = target_zoom * 2.0
			pivot.min_zoom = target_zoom * 0.5
		camera.position.z = target_zoom

	# Find UI elements
	slice_controls = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/SliceControls")
	if slice_controls:
		slice_slider_x = slice_controls.get_node_or_null("SliderX")
		slice_slider_y = slice_controls.get_node_or_null("SliderY")
		slice_slider_z = slice_controls.get_node_or_null("SliderZ")

	chisel_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/ChiselButton")
	mark_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/MarkButton")
	slice_toggle_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/SliceToggleButton")
	undo_btn = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/HBoxContainer/UndoButton")

	var top_info = get_node_or_null("CanvasLayer/Control/MarginContainer/TopInfoBar/HBoxContainer")
	if top_info:
		round_label = top_info.get_node_or_null("RoundLabel")
		hp_label = top_info.get_node_or_null("HPLabel")
		combo_label = top_info.get_node_or_null("ComboLabel")
		timer_label = top_info.get_node_or_null("TimerLabel")
		var boss_container = top_info.get_node_or_null("BossContainer")
		if boss_container:
			boss_name_label = boss_container.get_node_or_null("BossNameLabel")
			boss_hp_bar = boss_container.get_node_or_null("BossHPBar")

	var touch_controls = get_node_or_null("CanvasLayer/Control")
	if touch_controls and touch_controls is MobileTouchControls:
		touch_controls.chisel_voxel_requested.connect(on_chisel_requested)
		touch_controls.mark_voxel_requested.connect(on_mark_requested)
		touch_controls.hover_voxel_requested.connect(on_hover_requested)

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
	if slice_toggle_btn:
		slice_toggle_btn.pressed.connect(_on_slice_toggle_pressed)
	if undo_btn:
		undo_btn.pressed.connect(undo_last_move)

	_update_ui_state()

	# Dynamically set max_zoom based on grid size and adjust camera
	if camera:
		var max_dim = max(grid_size.x, max(grid_size.y, grid_size.z))
		var target_zoom = float(max_dim) * 2.5
		# We assume the parent is CameraPivot, which handles max_zoom
		var pivot = camera.get_parent()
		if pivot and "max_zoom" in pivot:
			pivot.max_zoom = target_zoom * 2.0
			pivot.min_zoom = target_zoom * 0.5
		camera.position.z = target_zoom

func _process(delta: float) -> void:
	if is_puzzle_active:
		time_elapsed = (Time.get_ticks_msec() - start_time) / 1000.0
		if timer_label:
			timer_label.text = "Time: %.1f" % time_elapsed

func _update_ui_state() -> void:
	if hp_label:
		hp_label.text = "HP: %d/3" % player_hp
	if round_label:
		round_label.text = "Floor %d" % current_floor
	if boss_hp_bar:
		boss_hp_bar.max_value = max_boss_hp
		boss_hp_bar.value = boss_hp
	if boss_name_label:
		boss_name_label.text = "Maze Guardian F%d" % current_floor
	if combo_label:
		combo_label.text = "Combo: x%d" % combo

	if chisel_btn and mark_btn:
		chisel_btn.disabled = (current_mode == EditMode.DESTROY)
		mark_btn.disabled = (current_mode == EditMode.MARK)

func _on_chisel_mode_selected() -> void:
	current_mode = EditMode.DESTROY
	_update_ui_state()
	var touch_controls = get_node_or_null("CanvasLayer/Control")
	if touch_controls and touch_controls is MobileTouchControls:
		touch_controls.set_touch_mode(touch_controls.TouchMode.CHISEL)

func _on_mark_mode_selected() -> void:
	current_mode = EditMode.MARK
	_update_ui_state()
	var touch_controls = get_node_or_null("CanvasLayer/Control")
	if touch_controls and touch_controls is MobileTouchControls:
		touch_controls.set_touch_mode(touch_controls.TouchMode.MARK)

func _on_slice_toggle_pressed() -> void:
	if slice_controls:
		slice_controls.visible = not slice_controls.visible

func _generate_solution() -> void:
	# Generate a basic boolean array for the target shape solution
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			for z in range(grid_size.z):
				var pos = Vector3i(x, y, z)
				# Simple pattern for testing: inner core is filled, outer is not
				var is_filled = (x > 0 and x < grid_size.x - 1) and (y > 0 and y < grid_size.y - 1) and (z > 0 and z < grid_size.z - 1)
				target_solution[pos] = is_filled

func _build_grid() -> void:
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			for z in range(grid_size.z):
				var pos = Vector3i(x, y, z)
				var block = block_scene.instantiate() as PicrossBlock
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
		var block = blocks[pos] as PicrossBlock

		# If it's outside the slice bounds, hide it
		if pos.x > slice_max.x or pos.y > slice_max.y or pos.z > slice_max.z:
			if block.current_state != block.BlockState.DESTROYED:
				block.set_state(block.BlockState.HIDDEN_BY_SLICE)
		else:
			# Only restore if it was previously hidden by slice, not if destroyed
			if block.current_state == block.BlockState.HIDDEN_BY_SLICE:
				block.set_state(block.BlockState.UNBROKEN)

func _update_clues() -> void:
	# Clear existing labels
	for child in labels_container.get_children():
		child.queue_free()

	# Recalculate based on current slice
	# X clues (along X axis, placed on the exposed Y-Z face)
	for y in range(slice_max.y + 1):
		for z in range(slice_max.z + 1):
			var counts = _calculate_clue(Vector3i(0, y, z), Vector3i(1, 0, 0), slice_max.x + 1)
			if counts.size() > 0:
				var exposed_pos = Vector3(slice_max.x, y, z)
				_add_clue_label(exposed_pos, Vector3.RIGHT, counts)

	# Y clues
	for x in range(slice_max.x + 1):
		for z in range(slice_max.z + 1):
			var counts = _calculate_clue(Vector3i(x, 0, z), Vector3i(0, 1, 0), slice_max.y + 1)
			if counts.size() > 0:
				var exposed_pos = Vector3(x, slice_max.y, z)
				_add_clue_label(exposed_pos, Vector3.UP, counts)

	# Z clues
	for x in range(slice_max.x + 1):
		for y in range(slice_max.y + 1):
			var counts = _calculate_clue(Vector3i(x, y, 0), Vector3i(0, 0, 1), slice_max.z + 1)
			if counts.size() > 0:
				var exposed_pos = Vector3(x, y, slice_max.z)
				_add_clue_label(exposed_pos, Vector3.BACK, counts)

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

func _add_clue_label(grid_pos: Vector3, normal: Vector3, counts: Array) -> void:
	var label = Label3D.new()
	var text = ""

	if counts.size() == 1:
		text = str(counts[0])
	elif counts.size() == 2:
		text = "(" + str(counts[0] + counts[1]) + ")"
	elif counts.size() >= 3:
		var sum = 0
		for c in counts:
			sum += c
		text = "[" + str(sum) + "]"

	label.text = text

	# Adjust position slightly outside the block face
	var world_pos = grid_pos - Vector3(grid_size) / 2.0 + Vector3(0.5, 0.5, 0.5)
	label.position = world_pos + (normal * 0.51)

	# Align to face normal
	if normal == Vector3.RIGHT:
		label.rotation_degrees.y = 90
	elif normal == Vector3.UP:
		label.rotation_degrees.x = -90
	elif normal == Vector3.BACK:
		label.rotation_degrees.y = 0

	label.pixel_size = 0.05
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.outline_render_priority = 0
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.8)
	labels_container.add_child(label)


# Signal handlers for MobileTouchControls
func on_chisel_requested(grid_pos: Vector3i, is_player_action: bool = true) -> void:
	if not blocks.has(grid_pos):
		return
	var block = blocks[grid_pos] as PicrossBlock

	if block.current_state == block.BlockState.MARKED:
		# Marked blocks are protected from chiseling
		if OS.has_feature("mobile") and is_player_action:
			Input.vibrate_handheld(20) # Small bump indicating protection
		return

	if block.current_state == block.BlockState.UNBROKEN:
		# If this is not a player action, we append it to the last move (for undoing chain reactions)
		_record_move(grid_pos, block.current_state, not is_player_action)

		# If it's a target block, it's a mistake
		if target_solution.get(grid_pos, false):
			_destroy_block(block, is_player_action) # We break it to reveal the mistake underneath
			_handle_mistake(is_player_action)
		else:
			_destroy_block(block, is_player_action)
			if OS.has_feature("mobile") and is_player_action:
				Input.vibrate_handheld(40) # Haptic feedback on valid move
	elif block.current_state != block.BlockState.DESTROYED:
		_handle_mistake(is_player_action)

func on_mark_requested(grid_pos: Vector3i) -> void:
	if not blocks.has(grid_pos):
		return
	var block = blocks[grid_pos] as PicrossBlock
	if block.current_state == block.BlockState.UNBROKEN:
		_record_move(grid_pos, block.current_state)
		block.set_state(block.BlockState.MARKED)
		if OS.has_feature("mobile"):
			Input.vibrate_handheld(40)
	elif block.current_state == block.BlockState.MARKED:
		_record_move(grid_pos, block.current_state)
		block.set_state(block.BlockState.UNBROKEN)
		if OS.has_feature("mobile"):
			Input.vibrate_handheld(40)
	else:
		_handle_mistake()

func _record_move(pos: Vector3i, previous_state: int, append_to_last: bool = false) -> void:
	if append_to_last and move_history.size() > 0:
		var last_entry = move_history.back()
		if typeof(last_entry) == TYPE_ARRAY:
			last_entry.append({"pos": pos, "state": previous_state})
		else:
			var new_array = [last_entry, {"pos": pos, "state": previous_state}]
			move_history[move_history.size() - 1] = new_array
	else:
		move_history.append({"pos": pos, "state": previous_state})
	emit_signal("history_updated", true)

func undo_last_move() -> void:
	if move_history.is_empty():
		return
	var last_move = move_history.pop_back()

	if typeof(last_move) == TYPE_ARRAY:
		# Undo in reverse order
		for i in range(last_move.size() - 1, -1, -1):
			var move = last_move[i]
			var pos = move["pos"]
			var prev_state = move["state"]
			if blocks.has(pos):
				var block = blocks[pos] as PicrossBlock
				block.set_state(prev_state)
	else:
		var pos = last_move["pos"]
		var prev_state = last_move["state"]
		if blocks.has(pos):
			var block = blocks[pos] as PicrossBlock
			block.set_state(prev_state)

	_update_slicing() # Ensure visibility is correct if hidden by slice
	emit_signal("history_updated", not move_history.is_empty())

func on_hover_requested(grid_pos: Vector3i, is_hover: bool) -> void:
	if not blocks.has(grid_pos):
		if hovered_block:
			hovered_block.set_highlight(false)
			hovered_block = null
		return

	var block = blocks[grid_pos] as PicrossBlock
	if is_hover:
		if hovered_block and hovered_block != block:
			hovered_block.set_highlight(false)
		hovered_block = block
		hovered_block.set_highlight(true)
	else:
		if hovered_block == block:
			hovered_block.set_highlight(false)
			hovered_block = null

func _handle_mistake(is_player_action: bool = true) -> void:
	if is_player_action:
		mistakes += 1
		combo = 0
		player_hp -= 1
		_update_ui_state()
		emit_signal("mistake_made", mistakes)

		if OS.has_feature("mobile"):
			Input.vibrate_handheld(120)
		if camera and camera.get_parent() and camera.get_parent().has_method("shake"):
			camera.get_parent().shake(0.3, 0.2)

	if player_hp <= 0:
		is_puzzle_active = false
		emit_signal("game_over")
		print("Game Over! Restarting floor.")
		await get_tree().create_timer(2.0).timeout
		base_grid_size = 3
		current_floor = 1
		start_level()

func _destroy_block(block: PicrossBlock, is_player_action: bool = true) -> void:
	block.set_state(block.BlockState.DESTROYED)
	if is_player_action:
		combo += 1
	_update_ui_state()
	_check_win_condition()
	emit_signal("voxel_destroyed", block.grid_position, is_player_action)

func _check_win_condition() -> void:
	if not is_puzzle_active: return

	# Win condition: All non-target blocks are DESTROYED.
	# We do NOT fail here if a target block is destroyed; that is handled at the time of chisel.
	for pos in blocks.keys():
		var block = blocks[pos] as PicrossBlock
		var is_target = target_solution.get(pos, false)

		if not is_target:
			if block.current_state != block.BlockState.DESTROYED:
				return

	# Puzzle Solved!
	is_puzzle_active = false
	print("Puzzle Solved! Revealing model...")
	emit_signal("puzzle_solved")
	_reveal_model()

func _reveal_model() -> void:
	# Hide all slice constraints
	if slice_controls:
		slice_controls.hide()
	slice_max = grid_size
	_update_slicing()

	# Clear clues
	for child in labels_container.get_children():
		child.queue_free()

	# Apply random stylish color to remaining blocks
	for pos in target_solution.keys():
		if target_solution[pos] and blocks.has(pos):
			var block = blocks[pos] as PicrossBlock
			if block.current_state == block.BlockState.UNBROKEN or block.current_state == block.BlockState.MARKED:
				block.base_material.albedo_color = Color(randf_range(0.2, 1.0), randf_range(0.2, 1.0), randf_range(0.2, 1.0))

	# Deal damage to Boss
	var time_bonus = max(0.0, 60.0 - time_elapsed) * 2.0
	var combo_bonus = combo * 5.0
	var damage = 50.0 + time_bonus + combo_bonus
	boss_hp -= damage
	_update_ui_state()

	await get_tree().create_timer(3.0).timeout

	if boss_hp <= 0:
		print("Boss Defeated! Advancing floor.")
		current_floor += 1
		base_grid_size = min(base_grid_size + 1, 5) # Max 5x5x5 for now to prevent lag
		emit_signal("floor_cleared")
		start_level()
	else:
		print("Next phase of the boss!")
		start_level() # Next puzzle, same floor