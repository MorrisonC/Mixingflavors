extends Node3D

class_name GridManager

@export var grid_size: Vector3i = Vector3i(5, 5, 5)
@export var block_scene: PackedScene = preload("res://scenes/Block.tscn")
@export var camera: Camera3D

# Internal storage
var blocks: Dictionary = {}
var target_solution: Dictionary = {}

var slice_max: Vector3i

@onready var labels_container: Node3D = $LabelsContainer

signal puzzle_solved
signal mistake_made(total_mistakes)
signal combo_updated(current_combo)

var mistakes: int = 0
var combo: int = 0

# UI Elements for slicing
@onready var slice_slider_x: HSlider = $CanvasLayer/Control/VBoxContainer/SliderX
@onready var slice_slider_y: HSlider = $CanvasLayer/Control/VBoxContainer/SliderY
@onready var slice_slider_z: HSlider = $CanvasLayer/Control/VBoxContainer/SliderZ
@onready var mode_toggle: CheckButton = $CanvasLayer/Control/ModeToggle

enum EditMode { DESTROY, MARK }
var current_mode: EditMode = EditMode.DESTROY

var hovered_block: PicrossBlock = null

func _ready() -> void:
	slice_max = grid_size - Vector3i(1, 1, 1)

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

	# Find UI elements that might have moved
	if not slice_slider_x:
		slice_slider_x = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/SliderX")
	if not slice_slider_y:
		slice_slider_y = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/SliderY")
	if not slice_slider_z:
		slice_slider_z = get_node_or_null("CanvasLayer/Control/MarginContainer/VBoxContainer/SliderZ")
	if not mode_toggle:
		mode_toggle = get_node_or_null("CanvasLayer/Control/MarginContainer/HBoxContainer/ModeToggle")

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

	if mode_toggle:
		mode_toggle.toggled.connect(_on_mode_toggled)

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

func _on_mode_toggled(button_pressed: bool) -> void:
	current_mode = EditMode.MARK if button_pressed else EditMode.DESTROY
	var touch_controls = get_node_or_null("CanvasLayer/Control")
	if touch_controls and touch_controls is MobileTouchControls:
		touch_controls.set_touch_mode(touch_controls.TouchMode.MARK if button_pressed else touch_controls.TouchMode.CHISEL)

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
	labels_container.add_child(label)


# Signal handlers for MobileTouchControls
func on_chisel_requested(grid_pos: Vector3i) -> void:
	if not blocks.has(grid_pos):
		return
	var block = blocks[grid_pos] as PicrossBlock
	if block.current_state == block.BlockState.UNBROKEN:
		_destroy_block(block)
		if OS.has_feature("mobile"):
			Input.vibrate_handheld(50) # Haptic feedback on valid move
	elif OS.has_feature("mobile"):
		Input.vibrate_handheld(150) # Haptic error feedback

func on_mark_requested(grid_pos: Vector3i) -> void:
	if not blocks.has(grid_pos):
		return
	var block = blocks[grid_pos] as PicrossBlock
	if block.current_state == block.BlockState.UNBROKEN:
		block.set_state(block.BlockState.MARKED)
		if OS.has_feature("mobile"):
			Input.vibrate_handheld(50)
	elif block.current_state == block.BlockState.MARKED:
		block.set_state(block.BlockState.UNBROKEN)
		if OS.has_feature("mobile"):
			Input.vibrate_handheld(50)
	elif OS.has_feature("mobile"):
		Input.vibrate_handheld(150)

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

func _destroy_block(block: PicrossBlock) -> void:
	block.set_state(block.BlockState.DESTROYED)
	# Play break sound here
	_check_win_condition()

func _check_win_condition() -> void:
	for pos in blocks.keys():
		var block = blocks[pos] as PicrossBlock
		var is_target = target_solution.get(pos, false)

		if is_target:
			# If a target block was destroyed, they lose or fail
			if block.current_state == block.BlockState.DESTROYED:
				print("Mistake made! Destroyed a target block.")
				# Handle mistake
		else:
			# If a non-target block is NOT destroyed, puzzle is not solved
			if block.current_state != block.BlockState.DESTROYED:
				return

	print("Puzzle Solved!")