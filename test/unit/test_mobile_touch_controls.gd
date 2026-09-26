extends GutTest

const MobileTouchControlsClass = preload("res://scripts/MobileTouchControls.gd")


class FakeGrid:
	extends Node3D
	var grid_size: Vector3i = Vector3i(1, 1, 1)
	var voxel_states: Dictionary = {}
	var blocks: Dictionary = {}

	func _init() -> void:
		voxel_states[Vector3i(0, 0, 0)] = {
			"cell_state": 0,
			"is_hidden_by_slice": false,
			"is_chiseled": false
		}

	func is_cell_chiseled(position: Vector3i) -> bool:
		var state: Dictionary = voxel_states.get(position, {})
		var cell_state: int = int(state.get("cell_state", 0))
		return cell_state == 2 or cell_state == 3


class FakePivot:
	extends Node3D
	var orbit_deltas: Array[Vector2] = []
	var zoom_amounts: Array[float] = []
	var end_count: int = 0

	func add_orbit_input(relative_motion: Vector2) -> void:
		orbit_deltas.append(relative_motion)

	func add_zoom_input(amount: float) -> void:
		zoom_amounts.append(amount)

	func end_orbit() -> void:
		end_count += 1


var controls: MobileTouchControls
var fake_grid: FakeGrid
var fake_pivot: FakePivot
var test_camera: Camera3D
var chisel_count: int = 0
var mark_count: int = 0
var last_voxel: Vector3i = Vector3i(-1, -1, -1)


func before_each() -> void:
	controls = MobileTouchControlsClass.new()
	add_child_autoqfree(controls)

	fake_grid = FakeGrid.new()
	add_child_autoqfree(fake_grid)
	fake_pivot = FakePivot.new()
	add_child_autoqfree(fake_pivot)
	test_camera = Camera3D.new()
	test_camera.position = Vector3(0.0, 0.0, 10.0)
	add_child_autoqfree(test_camera)
	test_camera.look_at(Vector3.ZERO, Vector3.UP)
	test_camera.current = true

	controls.camera = test_camera
	controls.camera_pivot = fake_pivot
	controls.grid_manager = fake_grid
	controls.set_manual_time_msec(1000.0)
	controls.chisel_voxel_requested.connect(_on_chisel_requested)
	controls.mark_voxel_requested.connect(_on_mark_requested)
	chisel_count = 0
	mark_count = 0
	last_voxel = Vector3i(-1, -1, -1)


func after_each() -> void:
	controls.set_manual_time_msec(-1.0)


func _on_chisel_requested(position: Vector3i) -> void:
	chisel_count += 1
	last_voxel = position


func _on_mark_requested(position: Vector3i) -> void:
	mark_count += 1
	last_voxel = position


func _center() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5


func _touch_press(index: int, position: Vector2, time_msec: float = 1000.0) -> InputEventScreenTouch:
	controls.set_manual_time_msec(time_msec)
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = true
	controls._gui_input(event)
	return event


func _touch_release(index: int, position: Vector2, time_msec: float = 1050.0, canceled: bool = false) -> InputEventScreenTouch:
	controls.set_manual_time_msec(time_msec)
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = false
	event.canceled = canceled
	controls._gui_input(event)
	return event


func _touch_drag(index: int, position: Vector2, relative: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = relative
	controls._gui_input(event)
	return event


func _mouse_press(position: Vector2, time_msec: float = 1000.0) -> InputEventMouseButton:
	controls.set_manual_time_msec(time_msec)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = true
	controls._gui_input(event)
	return event


func _mouse_release(position: Vector2, time_msec: float = 1050.0) -> InputEventMouseButton:
	controls.set_manual_time_msec(time_msec)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = false
	controls._gui_input(event)
	return event


func _mouse_motion(position: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.relative = relative
	controls._gui_input(event)
	return event


func test_tap_vs_drag_disambiguation() -> void:
	var event_press := InputEventScreenTouch.new()
	event_press.index = 0
	event_press.pressed = true
	event_press.position = Vector2(100.0, 100.0)
	controls._gui_input(event_press)
	assert_eq(controls.touch_start_pos, Vector2(100.0, 100.0), "Start position should be set")
	assert_false(controls.touch_dragged, "Should not be dragged on press")

	var event_drag_small := InputEventScreenDrag.new()
	event_drag_small.index = 0
	event_drag_small.position = Vector2(105.0, 105.0)
	controls._gui_input(event_drag_small)
	assert_false(controls.touch_dragged, "Small drag should not trigger dragged state")

	var event_release := InputEventScreenTouch.new()
	event_release.index = 0
	event_release.pressed = false
	event_release.position = Vector2(105.0, 105.0)
	controls._gui_input(event_release)
	assert_false(controls.touch_dragged, "Should not be dragged on release after small drag")


func test_drag_threshold_exceeded() -> void:
	var event_press := InputEventScreenTouch.new()
	event_press.index = 0
	event_press.pressed = true
	event_press.position = Vector2(100.0, 100.0)
	controls._gui_input(event_press)

	var event_drag_large := InputEventScreenDrag.new()
	event_drag_large.index = 0
	event_drag_large.position = Vector2(120.0, 120.0)
	controls._gui_input(event_drag_large)
	assert_true(controls.touch_dragged, "Large drag should trigger dragged state")


func test_tap_visible_voxel_applies_current_tool() -> void:
	var position: Vector2 = _center()
	assert_eq(controls._raycast_block(position), Vector3i(0, 0, 0), "Center ray should resolve the visible cell")

	_touch_press(0, position, 1000.0)
	_touch_release(0, position, 1040.0)

	assert_eq(chisel_count, 1, "A short tap should apply the chisel once")
	assert_eq(last_voxel, Vector3i(0, 0, 0), "The tapped voxel should be emitted")


func test_drag_over_voxel_orbits_without_tool_action() -> void:
	var position: Vector2 = _center()
	_touch_press(0, position, 1000.0)
	_touch_drag(0, position + Vector2(40.0, 0.0), Vector2(40.0, 0.0))
	_touch_release(0, position + Vector2(40.0, 0.0), 1100.0)

	assert_eq(chisel_count, 0, "A one-pointer drag must never chisel")
	assert_gt(fake_pivot.orbit_deltas.size(), 0, "A one-pointer drag should orbit the camera")
	assert_true(controls.touch_dragged == false, "Release should clear the compatibility drag flag")


func test_mouse_drag_orbits_without_tool_action() -> void:
	var position: Vector2 = _center()
	_mouse_press(position, 1000.0)
	_mouse_motion(position + Vector2(35.0, 0.0), Vector2(35.0, 0.0))
	_mouse_release(position + Vector2(35.0, 0.0), 1100.0)

	assert_eq(chisel_count, 0, "Mouse drag must not apply a tool")
	assert_gt(fake_pivot.orbit_deltas.size(), 0, "Mouse drag should orbit")


func test_canceled_touch_resets_without_tool_action() -> void:
	var position: Vector2 = _center()
	_touch_press(0, position, 1000.0)
	_touch_release(0, position, 1100.0, true)

	assert_eq(chisel_count, 0, "Canceled touch must not apply a tool")
	assert_false(controls.dragging_camera)
	assert_false(controls.dragging_block)
	assert_true(controls._touch_contacts.is_empty())


func test_focus_reset_does_not_apply_pending_tap() -> void:
	var position: Vector2 = _center()
	_touch_press(0, position, 1000.0)
	controls._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_touch_release(0, position, 1050.0)

	assert_eq(chisel_count, 0, "Focus loss must invalidate the pending tap")
	assert_true(controls._touch_contacts.is_empty())


func test_double_tap_uses_timestamp_policy_without_hidden_tool_switch() -> void:
	var position: Vector2 = _center()
	controls.last_tap_time = 1000.0
	controls.last_tap_pos = position
	assert_true(controls.should_treat_as_double_tap(1100.0, position), "A nearby tap inside the real interval is a double tap")
	assert_false(controls.should_treat_as_double_tap(1400.0, position), "A stale timestamp must not be a double tap")

	controls.current_mode = controls.TouchMode.CHISEL
	_touch_press(0, position, 2000.0)
	_touch_release(0, position, 2020.0)
	_touch_press(0, position, 2100.0)
	_touch_release(0, position, 2120.0)
	assert_eq(controls.current_mode, controls.TouchMode.CHISEL, "Tool changes must remain explicit toolbar selections")
	assert_eq(chisel_count, 1, "A double tap must not replay the tool action")


func test_emulated_mouse_pair_does_not_replay_touch_tap() -> void:
	var position: Vector2 = _center()
	_touch_press(0, position, 1000.0)
	_touch_release(0, position, 1040.0)
	_mouse_press(position, 1045.0)
	_mouse_release(position, 1080.0)

	assert_eq(chisel_count, 1, "An emulated mouse pair must not duplicate the touch action")
	assert_true(fake_pivot.orbit_deltas.is_empty(), "The emulated mouse pair must not start a second orbit")


func test_two_touch_pinch_zooms_and_never_edits() -> void:
	var center: Vector2 = _center()
	_touch_press(0, center - Vector2(60.0, 0.0), 1000.0)
	_touch_press(1, center + Vector2(60.0, 0.0), 1010.0)
	_touch_drag(1, center + Vector2(110.0, 0.0), Vector2(50.0, 0.0))
	_touch_release(0, center - Vector2(60.0, 0.0), 1100.0)
	_touch_release(1, center + Vector2(110.0, 0.0), 1100.0)

	assert_gt(fake_pivot.zoom_amounts.size(), 0, "Separating two touches should produce pinch zoom")
	assert_lt(fake_pivot.zoom_amounts[0], 0.0, "Separating fingers should zoom in")
	assert_eq(chisel_count, 0, "A pinch must never apply a tool")


func test_wheel_uses_pressed_state_and_factor() -> void:
	var wheel_press := InputEventMouseButton.new()
	wheel_press.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_press.pressed = true
	wheel_press.factor = 2.0
	controls._gui_input(wheel_press)
	assert_eq(fake_pivot.zoom_amounts.size(), 1, "A pressed wheel event should zoom")
	assert_almost_eq(fake_pivot.zoom_amounts[0], -2.0, 0.0001, "Wheel direction and factor should be preserved")

	var wheel_release := InputEventMouseButton.new()
	wheel_release.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_release.pressed = false
	wheel_release.factor = 2.0
	controls._gui_input(wheel_release)
	assert_eq(fake_pivot.zoom_amounts.size(), 1, "An unpressed wheel event must not zoom")


func test_input_lock_blocks_tap_drag_and_zoom() -> void:
	var position: Vector2 = _center()
	controls.input_locked = true
	_touch_press(0, position, 1000.0)
	_touch_drag(0, position + Vector2(40.0, 0.0), Vector2(40.0, 0.0))
	_touch_release(0, position + Vector2(40.0, 0.0), 1100.0)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.factor = 2.0
	controls._gui_input(wheel)

	assert_eq(chisel_count, 0, "Input lock must block tool actions")
	assert_true(fake_pivot.orbit_deltas.is_empty(), "Input lock must block orbit")
	assert_true(fake_pivot.zoom_amounts.is_empty(), "Input lock must block zoom")


# Contract change: a long press with no movement used to be a total no-op, so a
# 501ms press on a voxel produced no chisel, no mark and no sound - the action
# was silently dropped. It must still not switch tools or fire a double tap,
# but the release is now honoured.
func test_long_press_does_not_switch_tools_but_still_honours_the_tap() -> void:
	var position: Vector2 = _center()
	controls.current_mode = controls.TouchMode.CHISEL
	_touch_press(0, position, 1000.0)
	controls.set_manual_time_msec(1600.0)
	controls._process(0.0)
	_touch_release(0, position, 1650.0)

	assert_eq(controls.current_mode, controls.TouchMode.CHISEL, "Long press must not change tools")
	assert_true(controls.long_press_was_noop, "The long press itself is still a no-op for tools")
	assert_eq(chisel_count, 1, "A still long press must not swallow the player's tap")


func test_long_press_that_became_a_drag_still_applies_nothing() -> void:
	var position: Vector2 = _center()
	controls.current_mode = controls.TouchMode.CHISEL
	_touch_press(0, position, 1000.0)
	# Drag well past the slop so this is an orbit, not a tap.
	_touch_drag(0, position + Vector2(200.0, 0.0), Vector2(200.0, 0.0))
	controls.set_manual_time_msec(1600.0)
	controls._process(0.0)
	_touch_release(0, position + Vector2(200.0, 0.0), 1650.0)

	assert_eq(chisel_count, 0, "A long press that turned into a drag must not apply a tool")


func test_raycast_respects_grid_transform() -> void:
	fake_grid.position = Vector3(3.0, 0.0, 0.0)
	test_camera.position = Vector3(3.0, 0.0, 10.0)
	test_camera.look_at(fake_grid.global_position, Vector3.UP)
	assert_eq(controls._raycast_block(_center()), Vector3i(0, 0, 0), "Raycast should follow the grid transform")


func test_hover_uses_visible_unbroken_cells_only() -> void:
	var position: Vector2 = _center()
	controls._handle_hover(position)
	assert_eq(controls.hovered_voxel_pos, Vector3i(0, 0, 0), "Hover should select the unbroken cell")

	fake_grid.voxel_states[Vector3i(0, 0, 0)]["is_hidden_by_slice"] = true
	controls._handle_hover(position)
	assert_false(controls.is_hovering, "Hidden cells must not be hoverable")

	fake_grid.voxel_states[Vector3i(0, 0, 0)]["is_hidden_by_slice"] = false
	fake_grid.voxel_states[Vector3i(0, 0, 0)]["cell_state"] = 2
	controls._handle_hover(position)
	assert_false(controls.is_hovering, "Destroyed cells must not be hoverable")
