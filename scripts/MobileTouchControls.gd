extends Control
class_name MobileTouchControls

signal chisel_voxel_requested(grid_pos: Vector3i)
signal mark_voxel_requested(grid_pos: Vector3i)
signal hover_voxel_requested(grid_pos: Vector3i, is_hover: bool)
signal layer_slice_changed(axis: String, value: int)

enum TouchMode { CHISEL, MARK, PAINT, ROTATE }
var current_mode: TouchMode = TouchMode.CHISEL

func set_mode(mode: TouchMode) -> void:
	current_mode = mode

var touch_start_pos: Vector2 = Vector2.ZERO
var touch_dragged: bool = false
const DRAG_THRESHOLD: float = 12.0 # Pixels to distinguish tap from camera rotation drag

@export var camera_pivot: Node3D
@export var camera: Camera3D

var _touch_points: Dictionary = {}
var _initial_touch_distance: float = 0.0

var hovered_voxel_pos: Vector3i = Vector3i(-1, -1, -1)
var is_hovering: bool = false

func _ready() -> void:
	# Set Control properties to fill screen and pass input events
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_points[event.index] = event.position
			touch_start_pos = event.position
			touch_dragged = false
		else:
			_touch_points.erase(event.index)
			if not touch_dragged and _touch_points.size() == 0:
				_handle_single_tap(event.position)
				# Prevent default browser behavior on web when tap is consumed
				if OS.has_feature("web"):
					get_viewport().set_input_as_handled()

			if camera_pivot and camera_pivot.has_method("end_orbit"):
				camera_pivot.end_orbit()

		if _touch_points.size() == 2:
			var points = _touch_points.values()
			_initial_touch_distance = points[0].distance_to(points[1])

	elif event is InputEventScreenDrag:
		_touch_points[event.index] = event.position

		if _touch_points.size() == 1:
			if touch_start_pos.distance_to(event.position) > DRAG_THRESHOLD:
				touch_dragged = true
				_handle_camera_orbit(event.relative)
				if OS.has_feature("web"):
					get_viewport().set_input_as_handled()
		elif _touch_points.size() == 2:
			touch_dragged = true
			var points = _touch_points.values()
			var current_distance = points[0].distance_to(points[1])
			var diff = _initial_touch_distance - current_distance
			_handle_camera_zoom(diff * 0.05)
			_initial_touch_distance = current_distance
			if OS.has_feature("web"):
				get_viewport().set_input_as_handled()

	# Handle mouse for desktop testing
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				touch_start_pos = event.position
				touch_dragged = false
			else:
				if not touch_dragged:
					_handle_single_tap(event.position)
					if OS.has_feature("web"):
						get_viewport().set_input_as_handled()

				if camera_pivot and camera_pivot.has_method("end_orbit"):
					camera_pivot.end_orbit()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_handle_camera_zoom(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_handle_camera_zoom(1.0)

	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if touch_start_pos.distance_to(event.position) > DRAG_THRESHOLD:
				touch_dragged = true
				_handle_camera_orbit(event.relative)
				if OS.has_feature("web"):
					get_viewport().set_input_as_handled()
		else:
			_handle_hover(event.position)


func _handle_camera_orbit(relative: Vector2) -> void:
	if camera_pivot and camera_pivot.has_method("add_orbit_input"):
		camera_pivot.add_orbit_input(relative)
	elif camera_pivot and camera_pivot.has_method("_orbit_camera"):
		camera_pivot._orbit_camera(relative)
	elif camera_pivot:
		camera_pivot.rotation_degrees.y -= relative.x * 0.5
		camera_pivot.rotation_degrees.x -= relative.y * 0.5
		camera_pivot.rotation_degrees.x = clamp(camera_pivot.rotation_degrees.x, -85.0, 85.0)

func _handle_camera_zoom(amount: float) -> void:
	if camera_pivot and camera_pivot.has_method("add_zoom_input"):
		camera_pivot.add_zoom_input(amount)
	elif camera_pivot and camera_pivot.has_method("_zoom_camera"):
		camera_pivot._zoom_camera(amount)

func _handle_hover(hover_pos: Vector2) -> void:
	if not camera: return

	var ray_origin = camera.project_ray_origin(hover_pos)
	var ray_dir = camera.project_ray_normal(hover_pos) * 100.0
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir)
	var result = space_state.intersect_ray(query)

	if result:
		var hit_node = result.collider
		if hit_node.has_meta("grid_pos"):
			var grid_pos: Vector3i = hit_node.get_meta("grid_pos")
			if not is_hovering or grid_pos != hovered_voxel_pos:
				if is_hovering:
					emit_signal("hover_voxel_requested", hovered_voxel_pos, false)
				hovered_voxel_pos = grid_pos
				is_hovering = true
				emit_signal("hover_voxel_requested", grid_pos, true)
			return

	if is_hovering:
		emit_signal("hover_voxel_requested", hovered_voxel_pos, false)
		is_hovering = false

func _handle_single_tap(tap_pos: Vector2) -> void:
	if not camera: return

	var ray_origin = camera.project_ray_origin(tap_pos)
	var ray_dir = camera.project_ray_normal(tap_pos) * 100.0
	var space_state = camera.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir)
	var result = space_state.intersect_ray(query)

	if result:
		var hit_node = result.collider
		if hit_node.has_meta("grid_pos"):
			var grid_pos: Vector3i = hit_node.get_meta("grid_pos")

			if current_mode == TouchMode.CHISEL:
				emit_signal("chisel_voxel_requested", grid_pos)
			elif current_mode == TouchMode.MARK:
				emit_signal("mark_voxel_requested", grid_pos)
			elif current_mode == TouchMode.PAINT:
				emit_signal("mark_voxel_requested", grid_pos)

func set_touch_mode(mode: TouchMode) -> void:
	current_mode = mode
	print("[MobileTouchControls] Switched mode to: ", mode)
