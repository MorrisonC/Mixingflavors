extends Control
class_name MobileTouchControls

signal chisel_voxel_requested(grid_pos: Vector3i)
signal mark_voxel_requested(grid_pos: Vector3i)
signal hover_voxel_requested(grid_pos: Vector3i, is_hover: bool)
signal layer_slice_changed(axis: String, value: int)
signal camera_rotated(delta_angle: float)

enum TouchMode { CHISEL, MARK, PAINT, ROTATE }
var current_mode: TouchMode = TouchMode.CHISEL

@export var camera_pivot: Node3D
@export var camera: Camera3D

# Test compatibility variables
var touch_start_pos: Vector2 = Vector2.ZERO
var touch_dragged: bool = false
const DRAG_THRESHOLD: float = 12.0

var dragging_camera: bool = false
var dragging_block: bool = false
var start_block_pos: Vector3i = Vector3i(-1, -1, -1)
var drag_locked_axis: int = -1 # -1: none, 0: X, 1: Y, 2: Z
var affected_blocks: Array = []

var hovered_voxel_pos: Vector3i = Vector3i(-1, -1, -1)
var is_hovering: bool = false

var last_tap_time: float = 0.0
const DOUBLE_TAP_THRESHOLD: float = 300.0 # ms

var press_start_time: float = 0.0
const LONG_PRESS_THRESHOLD: float = 500.0 # ms
var has_triggered_long_press: bool = false

func _process(_delta: float) -> void:
	if not touch_dragged and (dragging_block or dragging_camera) and press_start_time > 0:
		var current_time = Time.get_ticks_msec()
		if current_time - press_start_time > LONG_PRESS_THRESHOLD and not has_triggered_long_press:
			_handle_long_press()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

func _gui_input(event: InputEvent) -> void:
	# Mouse / Touch Pressed
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				touch_start_pos = event.position
				touch_dragged = false
				_on_press_start(event.position)
				if OS.has_feature("web"):
					get_viewport().set_input_as_handled()
			else:
				_on_press_end()
				if OS.has_feature("web"):
					get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_handle_camera_zoom(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_handle_camera_zoom(1.0)

	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if touch_start_pos.distance_to(event.position) > DRAG_THRESHOLD:
				touch_dragged = true
		if dragging_camera:
			_handle_camera_orbit(event.relative)
			if OS.has_feature("web"):
				get_viewport().set_input_as_handled()
		elif dragging_block:
			_handle_block_drag(event.position)
			if OS.has_feature("web"):
				get_viewport().set_input_as_handled()
		else:
			_handle_hover(event.position)

	# Touch events supporting single/multi-touch drag
	elif event is InputEventScreenTouch:
		if event.pressed:
			if event.index == 0:
				touch_start_pos = event.position
				touch_dragged = false
				_on_press_start(event.position)
			if OS.has_feature("web"):
				get_viewport().set_input_as_handled()
		else:
			if event.index == 0:
				_on_press_end()
			if OS.has_feature("web"):
				get_viewport().set_input_as_handled()

	elif event is InputEventScreenDrag:
		if event.index == 0:
			if touch_start_pos.distance_to(event.position) > DRAG_THRESHOLD:
				touch_dragged = true
			if dragging_camera:
				_handle_camera_orbit(event.relative)
			elif dragging_block:
				_handle_block_drag(event.position)
			if OS.has_feature("web"):
				get_viewport().set_input_as_handled()

func _on_press_start(screen_pos: Vector2) -> void:
	press_start_time = Time.get_ticks_msec()
	has_triggered_long_press = false

	var hit_pos = _raycast_block(screen_pos)
	if hit_pos != Vector3i(-1, -1, -1) and current_mode != TouchMode.ROTATE:
		dragging_block = true
		start_block_pos = hit_pos
		drag_locked_axis = -1
		affected_blocks = [start_block_pos]
		# Action applied on release for tap, or on drag for multi-block
	else:
		dragging_camera = true

func _on_press_end() -> void:
	var current_time = Time.get_ticks_msec()

	if dragging_block and not touch_dragged and not has_triggered_long_press:
		# Rapid taps should work immediately
		_apply_tool_action(start_block_pos)

	dragging_camera = false
	dragging_block = false
	affected_blocks.clear()
	press_start_time = 0.0
	if camera_pivot and camera_pivot.has_method("end_orbit"):
		camera_pivot.end_orbit()

func _handle_double_tap() -> void:
	var new_mode = TouchMode.MARK if current_mode == TouchMode.CHISEL else TouchMode.CHISEL
	_trigger_ui_mode_switch(new_mode)
	if OS.has_feature("mobile"): Input.vibrate_handheld(20)

func _handle_long_press() -> void:
	has_triggered_long_press = true
	_handle_double_tap()

func _trigger_ui_mode_switch(mode: TouchMode) -> void:
	# Trigger grid manager to switch mode so UI updates
	var grid = get_node_or_null("/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/GridManager")
	if not grid: grid = get_parent().get_parent()

	if grid and grid.has_method("_on_chisel_mode_selected"):
		if mode == TouchMode.CHISEL:
			grid._on_chisel_mode_selected()
		elif mode == TouchMode.MARK:
			grid._on_mark_mode_selected()

func _handle_block_drag(screen_pos: Vector2) -> void:
	var hit_pos = _raycast_block(screen_pos)
	if hit_pos != Vector3i(-1, -1, -1) and hit_pos != affected_blocks[-1]:
		if drag_locked_axis == -1:
			var diff = hit_pos - start_block_pos
			var abs_x = abs(diff.x)
			var abs_y = abs(diff.y)
			var abs_z = abs(diff.z)
			if abs_x > 0 or abs_y > 0 or abs_z > 0:
				_apply_tool_action(start_block_pos)
				if abs_x >= abs_y and abs_x >= abs_z:
					drag_locked_axis = 0
				elif abs_y >= abs_x and abs_y >= abs_z:
					drag_locked_axis = 1
				else:
					drag_locked_axis = 2

		if drag_locked_axis != -1:
			var is_on_line = false
			if drag_locked_axis == 0:
				is_on_line = (hit_pos.y == start_block_pos.y and hit_pos.z == start_block_pos.z)
			elif drag_locked_axis == 1:
				is_on_line = (hit_pos.x == start_block_pos.x and hit_pos.z == start_block_pos.z)
			elif drag_locked_axis == 2:
				is_on_line = (hit_pos.x == start_block_pos.x and hit_pos.y == start_block_pos.y)

			if is_on_line and not (hit_pos in affected_blocks):
				var last_pos = affected_blocks[-1]
				var step_dir = Vector3i(0, 0, 0)
				if drag_locked_axis == 0:
					step_dir.x = 1 if hit_pos.x > last_pos.x else -1
				elif drag_locked_axis == 1:
					step_dir.y = 1 if hit_pos.y > last_pos.y else -1
				elif drag_locked_axis == 2:
					step_dir.z = 1 if hit_pos.z > last_pos.z else -1

				var current_step = last_pos + step_dir
				while current_step != hit_pos + step_dir:
					if not (current_step in affected_blocks):
						affected_blocks.append(current_step)
						_apply_tool_action(current_step)
					current_step += step_dir

func _apply_tool_action(grid_pos: Vector3i) -> void:
	if current_mode == TouchMode.CHISEL:
		emit_signal("chisel_voxel_requested", grid_pos)
	elif current_mode == TouchMode.MARK or current_mode == TouchMode.PAINT:
		emit_signal("mark_voxel_requested", grid_pos)

func _raycast_block(screen_pos: Vector2) -> Vector3i:
	if not camera: return Vector3i(-1, -1, -1)

	# Math-based raycast against grid size
	var grid_manager = get_node_or_null("/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/GridManager")
	if not grid_manager:
		grid_manager = get_parent().get_parent() # Fallback if we are a child

	if not grid_manager or not grid_manager.has_method("get"):
		return Vector3i(-1, -1, -1)

	var grid_size = grid_manager.grid_size
	var voxel_states = grid_manager.voxel_states

	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)

	# AABB intersection
	# Grid bounds are from (0,0,0) to (grid_size.x, grid_size.y, grid_size.z) theoretically
	# Actual block positions are Vector3(x, y, z) - Vector3(grid_size) / 2.0 + Vector3(0.5, 0.5, 0.5)

	var offset = -Vector3(grid_size) / 2.0 + Vector3(0.5, 0.5, 0.5)

	var t = 0.0
	var step = 0.1
	var max_dist = 100.0

	while t < max_dist:
		var pos = ray_origin + ray_dir * t
		var local_pos = pos - offset
		var grid_pos = Vector3i(round(local_pos.x), round(local_pos.y), round(local_pos.z))

		if grid_pos.x >= 0 and grid_pos.x < grid_size.x and \
		   grid_pos.y >= 0 and grid_pos.y < grid_size.y and \
		   grid_pos.z >= 0 and grid_pos.z < grid_size.z:

			if voxel_states.has(grid_pos):
				var state = voxel_states[grid_pos]
				if not grid_manager.is_cell_chiseled(grid_pos) and not state.get("is_hidden_by_slice", false):
					# Check exact block AABB
					var block_center = Vector3(grid_pos) + offset
					var diff = pos - block_center
					if abs(diff.x) <= 0.45 and abs(diff.y) <= 0.45 and abs(diff.z) <= 0.45:
						return grid_pos
		t += step

	return Vector3i(-1, -1, -1)

func _handle_camera_orbit(relative: Vector2) -> void:
	if camera_pivot and camera_pivot.has_method("add_orbit_input"):
		camera_pivot.add_orbit_input(relative)
		emit_signal("camera_rotated", abs(relative.x * 0.01))
	elif camera_pivot and camera_pivot.has_method("_orbit_camera"):
		camera_pivot._orbit_camera(relative)
		emit_signal("camera_rotated", abs(relative.x * 0.01))
	elif camera_pivot:
		camera_pivot.rotation_degrees.y -= relative.x * 0.5
		camera_pivot.rotation_degrees.x -= relative.y * 0.5
		camera_pivot.rotation_degrees.x = clamp(camera_pivot.rotation_degrees.x, -85.0, 85.0)
		emit_signal("camera_rotated", deg_to_rad(abs(relative.x * 0.5)))

func _handle_camera_zoom(amount: float) -> void:
	if camera_pivot and camera_pivot.has_method("add_zoom_input"):
		camera_pivot.add_zoom_input(amount)
	elif camera_pivot and camera_pivot.has_method("_zoom_camera"):
		camera_pivot._zoom_camera(amount)

func _handle_hover(hover_pos: Vector2) -> void:
	var hit_pos = _raycast_block(hover_pos)
	if hit_pos != Vector3i(-1, -1, -1):
		if not is_hovering or hit_pos != hovered_voxel_pos:
			if is_hovering:
				emit_signal("hover_voxel_requested", hovered_voxel_pos, false)
			hovered_voxel_pos = hit_pos
			is_hovering = true
			emit_signal("hover_voxel_requested", hit_pos, true)
	else:
		if is_hovering:
			emit_signal("hover_voxel_requested", hovered_voxel_pos, false)
			is_hovering = false

func set_touch_mode(mode: TouchMode) -> void:
	current_mode = mode
	print("[MobileTouchControls] Switched mode to: ", mode)
