extends GutTest

const MobileTouchControlsClass = preload("res://scripts/MobileTouchControls.gd")
var controls

func before_each():
	controls = MobileTouchControlsClass.new()
	add_child(controls)
	controls._ready()

func after_each():
	controls.queue_free()

func test_tap_vs_drag_disambiguation():
	var event_press = InputEventScreenTouch.new()
	event_press.index = 0
	event_press.pressed = true
	event_press.position = Vector2(100, 100)
	controls._gui_input(event_press)

	assert_eq(controls.touch_start_pos, Vector2(100, 100), "Start position should be set")
	assert_false(controls.touch_dragged, "Should not be dragged on press")

	var event_drag_small = InputEventScreenDrag.new()
	event_drag_small.index = 0
	event_drag_small.position = Vector2(105, 105) # Drag < 12px
	controls._gui_input(event_drag_small)

	assert_false(controls.touch_dragged, "Small drag should not trigger dragged state")

	var event_release = InputEventScreenTouch.new()
	event_release.index = 0
	event_release.pressed = false
	event_release.position = Vector2(105, 105)

	# We can't directly check the raycast outcome without a camera, but we can verify it tries to call it
	# by checking the touched state
	controls._gui_input(event_release)
	assert_false(controls.touch_dragged, "Should not be dragged on release after small drag")

func test_drag_threshold_exceeded():
	var event_press = InputEventScreenTouch.new()
	event_press.index = 0
	event_press.pressed = true
	event_press.position = Vector2(100, 100)
	controls._gui_input(event_press)

	var event_drag_large = InputEventScreenDrag.new()
	event_drag_large.index = 0
	event_drag_large.position = Vector2(120, 120) # Drag > 12px
	controls._gui_input(event_drag_large)

	assert_true(controls.touch_dragged, "Large drag should trigger dragged state")
