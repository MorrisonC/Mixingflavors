extends Control
class_name MobileTouchControls

## Robust pointer and camera gestures for the 3-D puzzle surface.
##
## Every one-pointer press is also an orbit gesture.  The voxel under the
## press is retained only as a tap candidate; it is never edited by a drag.

signal chisel_voxel_requested(grid_pos: Vector3i)
signal mark_voxel_requested(grid_pos: Vector3i)
signal hover_voxel_requested(grid_pos: Vector3i, is_hover: bool)
signal layer_slice_changed(axis: String, value: int)
signal camera_rotated(delta_angle: float)

enum TouchMode { CHISEL, MARK, PAINT, ROTATE }

const INVALID_GRID_POSITION: Vector3i = Vector3i(-1, -1, -1)
const DRAG_THRESHOLD: float = 12.0
const DOUBLE_TAP_THRESHOLD: float = 300.0 ## Milliseconds.
const DOUBLE_TAP_THRESHOLD_MS: float = DOUBLE_TAP_THRESHOLD
const LONG_PRESS_THRESHOLD: float = 500.0 ## Milliseconds.
const EMULATED_EVENT_GRACE_MS: float = 180.0

var current_mode: TouchMode = TouchMode.CHISEL

@export_category("Scene References")
@export var camera_pivot: Node3D
@export var camera: Camera3D
## Optional explicit reference.  When unset, capability discovery is used.
@export var grid_manager: Node
@export var input_locked: bool = false:
	set(value):
		if input_locked == value:
			return
		input_locked = value
		if input_locked:
			_reset_gesture_state(true)

@export_category("Gesture Settings")
@export var two_touch_midpoint_orbit: bool = true
@export var pinch_zoom_sensitivity: float = 0.02
@export var double_tap_max_distance: float = 48.0
@export var voxel_size: float = 0.9

# Compatibility state retained for existing scene tooling and tests.
var touch_start_pos: Vector2 = Vector2.ZERO
var touch_dragged: bool = false
var dragging_camera: bool = false
var dragging_block: bool = false
var start_block_pos: Vector3i = INVALID_GRID_POSITION
var drag_locked_axis: int = -1
var affected_blocks: Array[Vector3i] = []
var hovered_voxel_pos: Vector3i = INVALID_GRID_POSITION
var is_hovering: bool = false
var last_tap_time: float = 0.0
var last_tap_pos: Vector2 = Vector2.ZERO
var press_start_time: float = 0.0
var has_triggered_long_press: bool = false
var long_press_was_noop: bool = false

var _touch_contacts: Dictionary = {}
var _touch_order: Array[int] = []
var _primary_touch_index: int = -1
var _touch_dragged: bool = false
var _pinch_active: bool = false
var _pinch_start_distance: float = 0.0
var _pinch_last_distance: float = 0.0
var _pinch_last_midpoint: Vector2 = Vector2.ZERO

var _mouse_down: bool = false
var _mouse_start_pos: Vector2 = Vector2.ZERO
var _mouse_last_pos: Vector2 = Vector2.ZERO
var _mouse_dragged: bool = false
var _mouse_tap_candidate: Vector3i = INVALID_GRID_POSITION
var _mouse_double_tap_hint: bool = false

# Compatibility entry points can synthesize a generic single pointer.
var _legacy_pointer_active: bool = false
var _legacy_pointer_candidate: Vector3i = INVALID_GRID_POSITION
var _legacy_pointer_position: Vector2 = Vector2.ZERO

# First source wins a gesture; the paired emulated source is ignored.
var _active_pointer_kind: StringName = &""
var _blocked_peer_kind: StringName = &""
var _blocked_peer_until_msec: int = 0
var _gesture_cancelled: bool = false
var _resolved_grid_manager: Node = null
var _manual_time_msec: float = -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _notification(what: int) -> void:
	# Focus loss and OS interruption do not reliably produce a release event.
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_reset_gesture_state(true)


func _process(_delta: float) -> void:
	if input_locked:
		if _has_active_gesture():
			_reset_gesture_state(true)
		return
	if press_start_time <= 0.0 or touch_dragged or has_triggered_long_press or _gesture_cancelled:
		return
	if _touch_contacts.size() > 1 or not (_mouse_down or _legacy_pointer_active or not _touch_contacts.is_empty()):
		return
	if _now_msec() - press_start_time >= LONG_PRESS_THRESHOLD:
		_handle_long_press()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if _event_is_canceled(event):
			_reset_gesture_state(true)
			_consume_input_event()
			return
		if event.pressed:
			_begin_mouse_press(event)
		else:
			_end_mouse_press(event)
		_consume_input_event()
		return

	if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if event.pressed and not _event_is_canceled(event):
			var direction: float = -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			_handle_camera_zoom(direction * _event_factor(event))
		_consume_input_event()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if input_locked:
		_reset_gesture_state(true)
		_consume_input_event()
		return
	if _event_is_canceled(event):
		_reset_gesture_state(true)
		_consume_input_event()
		return
	if _should_ignore_peer(&"mouse", event.position):
		_consume_input_event()
		return

	if _mouse_down:
		var motion: Vector2 = event.relative
		if motion.is_zero_approx():
			motion = event.position - _mouse_last_pos
		_mouse_last_pos = event.position
		if _mouse_start_pos.distance_to(event.position) >= DRAG_THRESHOLD:
			_mouse_dragged = true
			touch_dragged = true
			dragging_block = false
			affected_blocks.clear()
			_invalidate_tap_sequence()
		if not motion.is_zero_approx():
			# Once a held mouse actually moves, its camera orbit must not be
			# reinterpreted as a tool tap even if the movement is below the
			# visual drag threshold.
			_mouse_dragged = true
			touch_dragged = true
			_invalidate_tap_sequence()
		# No voxel-drag path is reachable from a held mouse button.
		_handle_camera_orbit(motion)
		_consume_input_event()
		return

	_handle_hover(event.position)
	_consume_input_event()


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if _event_is_canceled(event):
		_reset_gesture_state(true)
		_consume_input_event()
		return
	if input_locked:
		_reset_gesture_state(true)
		_consume_input_event()
		return
	if _should_ignore_peer(&"touch", event.position):
		_consume_input_event()
		return
	if event.pressed:
		_begin_touch_press(event)
	else:
		_end_touch_release(event)
	_consume_input_event()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if input_locked:
		_reset_gesture_state(true)
		_consume_input_event()
		return
	if _event_is_canceled(event):
		_reset_gesture_state(true)
		_consume_input_event()
		return
	if _should_ignore_peer(&"touch", event.position):
		_consume_input_event()
		return
	if not _touch_contacts.has(event.index):
		_consume_input_event()
		return

	var contact: Dictionary = _touch_contacts[event.index]
	var previous_position: Vector2 = contact.get("position", event.position)
	var motion: Vector2 = event.relative
	if motion.is_zero_approx():
		motion = event.position - previous_position
	contact["position"] = event.position
	contact["last_motion"] = motion
	_touch_contacts[event.index] = contact

	if _touch_contacts.size() >= 2:
		_update_pinch_gesture()
	elif event.position.distance_to(contact.get("start_position", event.position)) >= DRAG_THRESHOLD:
		contact["dragged"] = true
		_touch_contacts[event.index] = contact
		_touch_dragged = true
		touch_dragged = true
		dragging_block = false
		affected_blocks.clear()
		_invalidate_tap_sequence()
		_handle_camera_orbit(motion)
	_consume_input_event()


func _begin_mouse_press(event: InputEventMouseButton) -> void:
	if input_locked:
		_reset_gesture_state(true)
		return
	if _mouse_down or _should_ignore_peer(&"mouse", event.position) or not _touch_contacts.is_empty():
		return
	_active_pointer_kind = &"mouse"
	_mouse_down = true
	_mouse_start_pos = event.position
	_mouse_last_pos = event.position
	_mouse_dragged = false
	_mouse_double_tap_hint = _event_double_tap_hint(event)
	touch_start_pos = event.position
	touch_dragged = false
	_gesture_cancelled = false
	_blocked_peer_kind = &""
	_mouse_tap_candidate = _raycast_block(event.position)
	start_block_pos = _mouse_tap_candidate
	dragging_block = _mouse_tap_candidate != INVALID_GRID_POSITION and current_mode != TouchMode.ROTATE
	dragging_camera = true
	press_start_time = _now_msec()
	has_triggered_long_press = false
	long_press_was_noop = false


func _end_mouse_press(event: InputEventMouseButton) -> void:
	if input_locked:
		_reset_gesture_state(true)
		return
	if not _mouse_down:
		_consume_input_event()
		return
	var should_tap: bool = not _mouse_dragged and not touch_dragged and not has_triggered_long_press and not _gesture_cancelled
	var candidate: Vector3i = _mouse_tap_candidate
	var position: Vector2 = event.position
	var tap_time: float = _now_msec()
	var event_hint: bool = _mouse_double_tap_hint or _event_double_tap_hint(event)
	_mouse_down = false
	_mouse_dragged = false
	_mouse_double_tap_hint = false
	dragging_camera = false
	dragging_block = false
	press_start_time = 0.0
	_finish_orbit()
	if should_tap:
		_complete_tap(candidate, position, tap_time, event_hint)
	_reset_pointer_fields_after_release()
	_set_pointer_block_for_peer(&"touch")
	_active_pointer_kind = &""


func _begin_touch_press(event: InputEventScreenTouch) -> void:
	if input_locked:
		_reset_gesture_state(true)
		return
	if _touch_contacts.has(event.index) or _touch_contacts.size() >= 2 or _mouse_down:
		return
	touch_start_pos = event.position
	touch_dragged = false
	_gesture_cancelled = false
	has_triggered_long_press = false
	long_press_was_noop = false
	_active_pointer_kind = &"touch"
	_blocked_peer_kind = &""
	var contact: Dictionary = {
		"position": event.position,
		"start_position": event.position,
		"start_time": _now_msec(),
		"dragged": false,
		"candidate": _raycast_block(event.position),
		"double_tap_hint": _event_double_tap_hint(event)
	}
	_touch_contacts[event.index] = contact
	_touch_order.append(event.index)
	if _touch_contacts.size() == 1:
		_primary_touch_index = event.index
		_start_single_pointer(event.position, contact.get("candidate", INVALID_GRID_POSITION), event.index)
	else:
		_touch_dragged = true
		touch_dragged = true
		_gesture_cancelled = true
		_invalidate_tap_sequence()
		_start_pinch_gesture()


func _end_touch_release(event: InputEventScreenTouch) -> void:
	if input_locked:
		_reset_gesture_state(true)
		return
	if not _touch_contacts.has(event.index):
		return
	var contact: Dictionary = _touch_contacts[event.index]
	var was_multi_touch: bool = _touch_contacts.size() >= 2
	var contact_dragged: bool = bool(contact.get("dragged", false))
	var candidate: Vector3i = contact.get("candidate", INVALID_GRID_POSITION)
	var position: Vector2 = event.position
	var tap_time: float = _now_msec()
	var event_hint: bool = _event_double_tap_hint(event) or bool(contact.get("double_tap_hint", false))
	_touch_contacts.erase(event.index)
	_touch_order.erase(event.index)

	if _touch_contacts.is_empty():
		var should_tap: bool = not was_multi_touch and not contact_dragged and not _touch_dragged and not touch_dragged and not has_triggered_long_press and not _gesture_cancelled
		dragging_camera = false
		dragging_block = false
		press_start_time = 0.0
		_finish_orbit()
		if should_tap:
			_complete_tap(candidate, position, tap_time, event_hint)
		_reset_pointer_fields_after_release()
		_set_pointer_block_for_peer(&"mouse")
		_active_pointer_kind = &""
	else:
		# A remaining finger continues as orbit-only; it can never become a
		# tap after a pinch.
		_touch_dragged = true
		touch_dragged = true
		_gesture_cancelled = true
		_pinch_active = false
		if _touch_contacts.size() == 1:
			var remaining_index: int = _touch_order[0]
			var remaining: Dictionary = _touch_contacts[remaining_index]
			remaining["start_position"] = remaining.get("position", event.position)
			remaining["dragged"] = true
			_touch_contacts[remaining_index] = remaining
			_primary_touch_index = remaining_index
		dragging_camera = true


func _start_single_pointer(screen_pos: Vector2, candidate: Vector3i, pointer_index: int) -> void:
	start_block_pos = candidate
	dragging_block = candidate != INVALID_GRID_POSITION and current_mode != TouchMode.ROTATE
	dragging_camera = true
	_touch_dragged = false
	press_start_time = _now_msec()
	_primary_touch_index = pointer_index
	affected_blocks.clear()
	if dragging_block:
		affected_blocks.append(candidate)


func _start_pinch_gesture() -> void:
	_pinch_active = true
	_pinch_start_distance = _touch_distance()
	_pinch_last_distance = _pinch_start_distance
	_pinch_last_midpoint = _touch_midpoint()


func _update_pinch_gesture() -> void:
	if _touch_contacts.size() < 2:
		_pinch_active = false
		return
	if not _pinch_active:
		_start_pinch_gesture()
		return
	var current_distance: float = _touch_distance()
	var current_midpoint: Vector2 = _touch_midpoint()
	if current_distance > 0.0 and _pinch_last_distance > 0.0:
		_handle_camera_zoom((_pinch_last_distance - current_distance) * pinch_zoom_sensitivity)
	if two_touch_midpoint_orbit:
		_handle_camera_orbit(current_midpoint - _pinch_last_midpoint)
	_pinch_last_distance = current_distance
	_pinch_last_midpoint = current_midpoint


func _touch_distance() -> float:
	if _touch_contacts.size() < 2:
		return 0.0
	var first: Dictionary = _touch_contacts[_touch_order[0]]
	var second: Dictionary = _touch_contacts[_touch_order[1]]
	return first.get("position", Vector2.ZERO).distance_to(second.get("position", Vector2.ZERO))


func _touch_midpoint() -> Vector2:
	if _touch_contacts.is_empty():
		return Vector2.ZERO
	var first: Dictionary = _touch_contacts[_touch_order[0]]
	if _touch_contacts.size() == 1:
		return first.get("position", Vector2.ZERO)
	var second: Dictionary = _touch_contacts[_touch_order[1]]
	return (first.get("position", Vector2.ZERO) + second.get("position", Vector2.ZERO)) * 0.5


## Compatibility entry point for old direct callers.
func _on_press_start(screen_pos: Vector2) -> void:
	if input_locked:
		_reset_gesture_state(true)
		return
	_reset_pointer_fields_after_release()
	_legacy_pointer_active = true
	_active_pointer_kind = &"generic"
	_legacy_pointer_candidate = _raycast_block(screen_pos)
	_legacy_pointer_position = screen_pos
	touch_start_pos = screen_pos
	touch_dragged = false
	_gesture_cancelled = false
	has_triggered_long_press = false
	long_press_was_noop = false
	_start_single_pointer(screen_pos, _legacy_pointer_candidate, -1)


## Compatibility release entry point.  It is tap-only when no drag occurred.
func _on_press_end() -> void:
	if not _legacy_pointer_active:
		return
	var should_tap: bool = not touch_dragged and not has_triggered_long_press and not _gesture_cancelled
	var candidate: Vector3i = _legacy_pointer_candidate
	var position: Vector2 = _legacy_pointer_position
	var tap_time: float = _now_msec()
	_legacy_pointer_active = false
	dragging_camera = false
	dragging_block = false
	press_start_time = 0.0
	_finish_orbit()
	if should_tap:
		_complete_tap(candidate, position, tap_time, false)
	_reset_pointer_fields_after_release()
	_active_pointer_kind = &""


## Former line-edit hook.  It is intentionally safe and orbit-only.
func _handle_block_drag(_screen_pos: Vector2) -> void:
	if input_locked:
		return
	touch_dragged = true
	_touch_dragged = true
	_invalidate_tap_sequence()


func _complete_tap(candidate: Vector3i, screen_position: Vector2, event_time_msec: float, event_double_tap_hint: bool) -> void:
	if input_locked or _gesture_cancelled or current_mode == TouchMode.ROTATE:
		return
	var is_double: bool = should_treat_as_double_tap(event_time_msec, screen_position, event_double_tap_hint)
	if is_double:
		last_tap_time = 0.0
		last_tap_pos = Vector2.ZERO
		_handle_double_tap()
		return
	last_tap_time = event_time_msec
	last_tap_pos = screen_position
	if candidate != INVALID_GRID_POSITION and _is_visible_unbroken(candidate):
		_apply_tool_action(candidate)


## Uses both a real millisecond interval and the engine hint only as a
## confirmation.  A stale event hint cannot manufacture a double tap.
func should_treat_as_double_tap(event_time_msec: float, screen_position: Vector2, event_hint: bool = false) -> bool:
	if last_tap_time <= 0.0:
		return false
	var elapsed: float = event_time_msec - last_tap_time
	if elapsed < 0.0 or elapsed > DOUBLE_TAP_THRESHOLD or screen_position.distance_to(last_tap_pos) > double_tap_max_distance:
		return false
	return event_hint or elapsed <= DOUBLE_TAP_THRESHOLD


func is_double_tap(event_time_msec: float, screen_position: Vector2, event_hint: bool = false) -> bool:
	return should_treat_as_double_tap(event_time_msec, screen_position, event_hint)


func _invalidate_tap_sequence() -> void:
	last_tap_time = 0.0
	last_tap_pos = Vector2.ZERO


func _handle_double_tap() -> void:
	if input_locked:
		return
	var new_mode: TouchMode = current_mode
	if current_mode == TouchMode.CHISEL:
		new_mode = TouchMode.MARK
	elif current_mode == TouchMode.MARK:
		new_mode = TouchMode.CHISEL
	else:
		return
	current_mode = new_mode
	_trigger_ui_mode_switch(new_mode)
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(20)


func _handle_long_press() -> void:
	if input_locked:
		_reset_gesture_state(true)
		return
	# Deliberate safe no-op/reset.  It must not call double-tap or a tool.
	has_triggered_long_press = true
	long_press_was_noop = true
	touch_dragged = true
	_touch_dragged = true
	_gesture_cancelled = true
	_reset_gesture_state(true)
	has_triggered_long_press = true
	long_press_was_noop = true
	touch_dragged = true


func _trigger_ui_mode_switch(mode: TouchMode) -> void:
	if input_locked:
		return
	var grid: Node = _find_grid_manager()
	if not is_instance_valid(grid):
		return
	if mode == TouchMode.CHISEL and grid.has_method("_on_chisel_mode_selected"):
		grid.call("_on_chisel_mode_selected")
	elif mode == TouchMode.MARK and grid.has_method("_on_mark_mode_selected"):
		grid.call("_on_mark_mode_selected")


func _apply_tool_action(grid_pos: Vector3i) -> void:
	if input_locked or not _is_visible_unbroken(grid_pos):
		return
	if current_mode == TouchMode.CHISEL:
		chisel_voxel_requested.emit(grid_pos)
	elif current_mode == TouchMode.MARK or current_mode == TouchMode.PAINT:
		mark_voxel_requested.emit(grid_pos)


func _handle_camera_orbit(relative: Vector2) -> void:
	if input_locked or relative.is_zero_approx() or not is_instance_valid(camera_pivot):
		return
	if camera_pivot.has_method("add_orbit_input"):
		camera_pivot.call("add_orbit_input", relative)
		camera_rotated.emit(absf(relative.x * 0.01))
	elif camera_pivot.has_method("_orbit_camera"):
		camera_pivot.call("_orbit_camera", relative)
		camera_rotated.emit(absf(relative.x * 0.01))
	else:
		camera_pivot.rotation_degrees.y -= relative.x * 0.5
		camera_pivot.rotation_degrees.x -= relative.y * 0.5
		camera_pivot.rotation_degrees.x = clampf(camera_pivot.rotation_degrees.x, -85.0, 85.0)
		camera_rotated.emit(deg_to_rad(absf(relative.x * 0.5)))


func _handle_camera_zoom(amount: float, factor: float = 1.0) -> void:
	if input_locked or not is_instance_valid(camera_pivot) or not is_finite(amount) or not is_finite(factor) or factor <= 0.0:
		return
	var effective_amount: float = amount * factor
	if camera_pivot.has_method("add_zoom_input"):
		camera_pivot.call("add_zoom_input", effective_amount)
	elif camera_pivot.has_method("_zoom_camera"):
		camera_pivot.call("_zoom_camera", effective_amount)


func _handle_hover(hover_pos: Vector2) -> void:
	if input_locked:
		_clear_hover()
		return
	var hit_pos: Vector3i = _raycast_block(hover_pos)
	if hit_pos != INVALID_GRID_POSITION:
		if not is_hovering or hit_pos != hovered_voxel_pos:
			if is_hovering:
				hover_voxel_requested.emit(hovered_voxel_pos, false)
			hovered_voxel_pos = hit_pos
			is_hovering = true
			hover_voxel_requested.emit(hit_pos, true)
	else:
		_clear_hover()


func _clear_hover() -> void:
	if is_hovering:
		hover_voxel_requested.emit(hovered_voxel_pos, false)
	is_hovering = false
	hovered_voxel_pos = INVALID_GRID_POSITION


## Cancel without emitting a tool request.  Safe for focus-loss callbacks.
func cancel_gesture() -> void:
	_reset_gesture_state(true)


func _cancel_gesture() -> void:
	_reset_gesture_state(true)


func reset_gesture_state() -> void:
	_reset_gesture_state(true)


func _reset_gesture_state(clear_tap_history: bool = false) -> void:
	_clear_hover()
	if dragging_camera or _pinch_active:
		_finish_orbit()
	_touch_contacts.clear()
	_touch_order.clear()
	_primary_touch_index = -1
	_touch_dragged = false
	_pinch_active = false
	_pinch_start_distance = 0.0
	_pinch_last_distance = 0.0
	_pinch_last_midpoint = Vector2.ZERO
	_mouse_down = false
	_mouse_dragged = false
	_mouse_double_tap_hint = false
	_mouse_tap_candidate = INVALID_GRID_POSITION
	_legacy_pointer_active = false
	_legacy_pointer_candidate = INVALID_GRID_POSITION
	_legacy_pointer_position = Vector2.ZERO
	_gesture_cancelled = false
	_active_pointer_kind = &""
	_blocked_peer_kind = &""
	_blocked_peer_until_msec = 0
	dragging_camera = false
	dragging_block = false
	start_block_pos = INVALID_GRID_POSITION
	drag_locked_axis = -1
	affected_blocks.clear()
	press_start_time = 0.0
	touch_start_pos = Vector2.ZERO
	has_triggered_long_press = false
	long_press_was_noop = false
	touch_dragged = false
	if clear_tap_history:
		last_tap_time = 0.0
		last_tap_pos = Vector2.ZERO


func _reset_pointer_fields_after_release() -> void:
	_touch_contacts.clear()
	_touch_order.clear()
	_primary_touch_index = -1
	_touch_dragged = false
	_pinch_active = false
	_pinch_start_distance = 0.0
	_pinch_last_distance = 0.0
	_pinch_last_midpoint = Vector2.ZERO
	_mouse_down = false
	_mouse_dragged = false
	_mouse_double_tap_hint = false
	_mouse_tap_candidate = INVALID_GRID_POSITION
	dragging_camera = false
	dragging_block = false
	start_block_pos = INVALID_GRID_POSITION
	drag_locked_axis = -1
	affected_blocks.clear()
	press_start_time = 0.0
	touch_dragged = false
	_legacy_pointer_active = false
	_legacy_pointer_candidate = INVALID_GRID_POSITION
	_legacy_pointer_position = Vector2.ZERO
	_gesture_cancelled = false


func _finish_orbit() -> void:
	if is_instance_valid(camera_pivot) and camera_pivot.has_method("end_orbit"):
		camera_pivot.call("end_orbit")


func _set_pointer_block_for_peer(peer_kind: StringName) -> void:
	_blocked_peer_kind = peer_kind
	_blocked_peer_until_msec = int(_now_msec()) + int(EMULATED_EVENT_GRACE_MS)


func _should_ignore_peer(kind: StringName, _position: Vector2) -> bool:
	var now: int = int(_now_msec())
	if _blocked_peer_kind == kind and now <= _blocked_peer_until_msec:
		return true
	return _active_pointer_kind != &"" and _active_pointer_kind != kind


func _has_active_gesture() -> bool:
	return _mouse_down or _legacy_pointer_active or not _touch_contacts.is_empty() or dragging_camera or _pinch_active


func _event_is_canceled(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).canceled
	if event is InputEventScreenDrag:
		return (event as InputEventScreenDrag).canceled
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).canceled
	return false


func _event_double_tap_hint(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).double_tap
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).double_click
	return false


func _event_factor(event: InputEvent) -> float:
	if event is not InputEventMouseButton:
		return 1.0
	var factor: float = (event as InputEventMouseButton).factor
	return factor if is_finite(factor) and factor > 0.0 else 1.0


func _event_position_to_viewport(local_position: Vector2) -> Vector2:
	if not is_inside_tree():
		return local_position
	return get_global_transform_with_canvas() * local_position


## Raycast actual cell geometry after transforming the camera ray into world
## space.  This works for translated, rotated, and scaled grid roots.
func _raycast_block(screen_pos: Vector2) -> Vector3i:
	if input_locked:
		return INVALID_GRID_POSITION
	var active_camera: Camera3D = _resolve_camera()
	var grid: Node = _find_grid_manager()
	if not is_instance_valid(active_camera) or not is_instance_valid(grid):
		return INVALID_GRID_POSITION
	var grid_size: Vector3i = _get_grid_size(grid)
	if grid_size.x <= 0 or grid_size.y <= 0 or grid_size.z <= 0:
		return INVALID_GRID_POSITION
	var states: Dictionary = _get_voxel_states(grid)
	if states.is_empty() and not _grid_has_block_data(grid):
		return INVALID_GRID_POSITION
	var viewport_position: Vector2 = _event_position_to_viewport(screen_pos)
	var ray_origin: Vector3 = active_camera.project_ray_origin(viewport_position)
	var ray_direction: Vector3 = active_camera.project_ray_normal(viewport_position)
	if ray_direction.is_zero_approx():
		return INVALID_GRID_POSITION

	var nearest_distance: float = INF
	var nearest_position: Vector3i = INVALID_GRID_POSITION
	for z in range(grid_size.z):
		for y in range(grid_size.y):
			for x in range(grid_size.x):
				var position: Vector3i = Vector3i(x, y, z)
				if not _is_visible_unbroken(position, grid, states):
					continue
				var hit_distance: float = _ray_aabb_distance(ray_origin, ray_direction, _cell_world_bounds(grid, position, grid_size))
				if hit_distance >= 0.0 and hit_distance < nearest_distance:
					nearest_distance = hit_distance
					nearest_position = position
	return nearest_position


func _resolve_camera() -> Camera3D:
	if is_instance_valid(camera):
		return camera
	if not is_instance_valid(camera_pivot):
		return null
	if camera_pivot is Camera3D:
		return camera_pivot as Camera3D
	return _find_camera_descendant(camera_pivot)


func _find_camera_descendant(root: Node) -> Camera3D:
	var queue: Array[Node] = [root]
	var visited: Dictionary = {}
	while not queue.is_empty():
		var current: Node = queue.pop_front()
		if visited.has(current):
			continue
		visited[current] = true
		if current is Camera3D:
			return current as Camera3D
		for child_value in current.get_children():
			queue.append(child_value as Node)
	return null


func _cell_world_bounds(grid: Node, position: Vector3i, grid_size: Vector3i) -> AABB:
	var block: Node = null
	var blocks_value: Variant = grid.get("blocks")
	if blocks_value is Dictionary and blocks_value.has(position):
		var block_value: Variant = blocks_value[position]
		if block_value is Node:
			block = block_value as Node
	var half_extent: float = maxf(voxel_size, 0.01) * 0.5
	if is_instance_valid(block) and block is Node3D:
		var block_3d: Node3D = block as Node3D
		var block_basis: Basis = block_3d.global_transform.basis
		var extents: Vector3 = Vector3(half_extent * block_basis.x.length(), half_extent * block_basis.y.length(), half_extent * block_basis.z.length())
		return AABB(block_3d.global_position - extents, extents * 2.0)
	var grid_transform: Transform3D = (grid as Node3D).global_transform if grid is Node3D else Transform3D.IDENTITY
	var local_center: Vector3 = Vector3(position) - Vector3(grid_size) * 0.5 + Vector3(0.5, 0.5, 0.5)
	var world_center: Vector3 = grid_transform * local_center
	var world_basis: Basis = grid_transform.basis
	var world_extents: Vector3 = Vector3(half_extent * world_basis.x.length(), half_extent * world_basis.y.length(), half_extent * world_basis.z.length())
	return AABB(world_center - world_extents, world_extents * 2.0)


func _ray_aabb_distance(origin: Vector3, direction: Vector3, bounds: AABB) -> float:
	var minimum: float = -1.0e20
	var maximum: float = 1.0e20
	for axis in range(3):
		var ray_component: float = direction[axis]
		var origin_component: float = origin[axis]
		var bounds_minimum: float = bounds.position[axis]
		var bounds_maximum: float = bounds.position[axis] + bounds.size[axis]
		if absf(ray_component) < 0.000001:
			if origin_component < bounds_minimum or origin_component > bounds_maximum:
				return -1.0
			continue
		var first_parameter: float = (bounds_minimum - origin_component) / ray_component
		var second_parameter: float = (bounds_maximum - origin_component) / ray_component
		if first_parameter > second_parameter:
			var swap: float = first_parameter
			first_parameter = second_parameter
			second_parameter = swap
		minimum = maxf(minimum, first_parameter)
		maximum = minf(maximum, second_parameter)
		if minimum > maximum:
			return -1.0
	if maximum < 0.0:
		return -1.0
	return maxf(minimum, 0.0)


func _get_grid_size(grid: Node) -> Vector3i:
	var value: Variant = grid.get("grid_size")
	if value is Vector3i:
		return value as Vector3i
	if value is Vector3:
		return Vector3i(value as Vector3)
	return Vector3i(5, 5, 5)


func _get_voxel_states(grid: Node) -> Dictionary:
	var value: Variant = grid.get("voxel_states")
	return value as Dictionary if value is Dictionary else {}


func _grid_has_block_data(grid: Node) -> bool:
	var value: Variant = grid.get("blocks")
	return value is Dictionary and not (value as Dictionary).is_empty()


func _is_visible_unbroken(position: Vector3i, grid_override: Node = null, states_override: Dictionary = {}) -> bool:
	if input_locked or not _is_valid_grid_position(position):
		return false
	var grid: Node = grid_override if is_instance_valid(grid_override) else _find_grid_manager()
	if not is_instance_valid(grid):
		return false
	var states: Dictionary = states_override if not states_override.is_empty() else _get_voxel_states(grid)
	if not states.is_empty():
		if not states.has(position):
			return false
		var state_value: Variant = states[position]
		if state_value is Dictionary:
			var state: Dictionary = state_value as Dictionary
			if bool(state.get("is_hidden_by_slice", false)) or bool(state.get("is_chiseled", false)) or bool(state.get("is_destroyed", false)):
				return false
			var cell_state: int = int(state.get("cell_state", 0))
			# GridManager's canonical CellState uses 2 for DESTROYED.
			if cell_state == 2:
				return false
	elif not _grid_has_block_data(grid):
		return false
	if grid.has_method("is_cell_chiseled") and bool(grid.call("is_cell_chiseled", position)):
		return false
	if grid.has_method("is_cell_visible") and not bool(grid.call("is_cell_visible", position)):
		return false
	if grid.has_method("is_cell_interactable"):
		return bool(grid.call("is_cell_interactable", position))
	if grid.has_method("is_cell_unbroken") and not bool(grid.call("is_cell_unbroken", position)):
		return false
	var blocks_value: Variant = grid.get("blocks")
	if blocks_value is Dictionary and blocks_value.has(position):
		var block_value: Variant = blocks_value[position]
		if block_value is Node3D:
			var block_3d: Node3D = block_value as Node3D
			if not block_3d.visible or (block_3d.is_inside_tree() and not block_3d.is_visible_in_tree()):
				return false
			if _has_node_property(block_3d, &"current_state"):
				var block_state: int = int(block_3d.get("current_state"))
				# VoxelBlock uses 0=UNBROKEN, 1=MARKED, 2=PAINTED,
				# 3=DESTROYED, and 4=HIDDEN_BY_SLICE.
				if block_state == 3 or block_state == 4:
					return false
	return true


func _is_valid_grid_position(position: Vector3i) -> bool:
	var grid: Node = _find_grid_manager()
	if not is_instance_valid(grid):
		return false
	var size: Vector3i = _get_grid_size(grid)
	return position.x >= 0 and position.x < size.x and position.y >= 0 and position.y < size.y and position.z >= 0 and position.z < size.z


func _has_node_property(node: Node, property_name: StringName) -> bool:
	if not is_instance_valid(node):
		return false
	for info_value in node.get_property_list():
		if info_value is Dictionary:
			var info: Dictionary = info_value as Dictionary
			if StringName(info.get("name", "")) == property_name:
				return true
	return false


func _is_grid_capable(candidate: Node) -> bool:
	if not is_instance_valid(candidate):
		return false
	var has_size: bool = _has_node_property(candidate, &"grid_size")
	var has_states: bool = _has_node_property(candidate, &"voxel_states")
	var has_blocks: bool = _has_node_property(candidate, &"blocks")
	var has_api: bool = candidate.has_method("is_cell_chiseled") or candidate.has_method("is_cell_visible") or candidate.has_method("is_cell_unbroken")
	return has_size and (has_states or has_blocks or has_api)


## Capability-based lookup; no level-specific scene path is embedded here.
func _find_grid_manager() -> Node:
	if is_instance_valid(_resolved_grid_manager) and _is_grid_capable(_resolved_grid_manager):
		return _resolved_grid_manager
	if is_instance_valid(grid_manager) and _is_grid_capable(grid_manager):
		_resolved_grid_manager = grid_manager
		return _resolved_grid_manager
	var visited: Dictionary = {}
	var candidates: Array[Node] = []
	var current: Node = self
	while is_instance_valid(current):
		if not visited.has(current):
			visited[current] = true
			candidates.append(current)
		var parent: Node = current.get_parent()
		if not is_instance_valid(parent):
			break
		current = parent
	current = self
	while is_instance_valid(current):
		if not visited.has(current):
			visited[current] = true
			candidates.append(current)
		current = current.owner
	for candidate in candidates:
		if _is_grid_capable(candidate):
			_resolved_grid_manager = candidate
			return _resolved_grid_manager
	if not is_inside_tree():
		return null
	var search_root: Node = get_tree().current_scene
	if is_instance_valid(search_root):
		var found: Node = _search_grid_descendants(search_root, visited)
		if is_instance_valid(found):
			_resolved_grid_manager = found
			return _resolved_grid_manager
	return null


func _search_grid_descendants(root: Node, visited: Dictionary) -> Node:
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var current: Node = queue.pop_front()
		if visited.has(current):
			continue
		visited[current] = true
		if _is_grid_capable(current):
			return current
		for child_value in current.get_children():
			queue.append(child_value as Node)
	return null


func _now_msec() -> float:
	return _manual_time_msec if _manual_time_msec >= 0.0 else float(Time.get_ticks_msec())


## Deterministic clock hook for focused tests; negative restores engine time.
func set_manual_time_msec(time_msec: float) -> void:
	_manual_time_msec = time_msec


func set_input_locked(locked: bool) -> void:
	input_locked = locked
	if input_locked:
		_reset_gesture_state(true)


func set_grid_manager(grid: Node) -> void:
	grid_manager = grid
	_resolved_grid_manager = grid if is_instance_valid(grid) else null


func get_grid_manager() -> Node:
	return _find_grid_manager()


func _consume_input_event() -> void:
	if not is_inside_tree():
		return
	var viewport: Viewport = get_viewport()
	if is_instance_valid(viewport):
		viewport.set_input_as_handled()


func set_touch_mode(mode: TouchMode) -> void:
	current_mode = mode
	print("[MobileTouchControls] Switched mode to: ", mode)
