extends Node3D

@export var rotation_speed: float = 0.5
@export var pan_speed: float = 0.05
@export var zoom_speed: float = 1.0
@export var min_zoom: float = 5.0
@export var max_zoom: float = 30.0

@export var touch_zoom_speed: float = 0.05
@export var touch_rotation_speed: float = 0.2

var _camera: Camera3D
var _is_dragging_orbit: bool = false
var _is_dragging_pan: bool = false

# For touch
var _touch_points: Dictionary = {}
var _initial_touch_distance: float = 0.0

func _ready() -> void:
	# Assume the Camera3D is a direct child
	for child in get_children():
		if child is Camera3D:
			_camera = child
			break
	if not _camera:
		push_error("CameraPivot needs a Camera3D child.")
	else:
		_camera.position.z = clamp(_camera.position.z, min_zoom, max_zoom)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				if Input.is_key_pressed(KEY_SHIFT):
					_is_dragging_pan = true
					_is_dragging_orbit = false
				else:
					_is_dragging_orbit = true
					_is_dragging_pan = false
			else:
				_is_dragging_orbit = false
				_is_dragging_pan = false

		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_camera(-zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_camera(zoom_speed)

	elif event is InputEventMouseMotion:
		if _is_dragging_orbit:
			_orbit_camera(event.relative)
		elif _is_dragging_pan:
			_pan_camera(event.relative)

	elif event is InputEventScreenTouch:
		if event.pressed:
			_touch_points[event.index] = event.position
		else:
			_touch_points.erase(event.index)

		if _touch_points.size() == 2:
			var points = _touch_points.values()
			_initial_touch_distance = points[0].distance_to(points[1])

	elif event is InputEventScreenDrag:
		_touch_points[event.index] = event.position

		if _touch_points.size() == 1:
			# Single touch drag to rotate
			_orbit_camera(event.relative * touch_rotation_speed)
		elif _touch_points.size() == 2:
			# Pinch to zoom
			var points = _touch_points.values()
			var current_distance = points[0].distance_to(points[1])
			var diff = _initial_touch_distance - current_distance
			_zoom_camera(diff * touch_zoom_speed)
			_initial_touch_distance = current_distance

func _orbit_camera(relative: Vector2) -> void:
	# Clamp small movements to avoid jitter in web/mobile
	if relative.length_squared() < 0.5:
		return

	rotation_degrees.y -= relative.x * rotation_speed
	rotation_degrees.x -= relative.y * rotation_speed
	rotation_degrees.x = clamp(rotation_degrees.x, -85.0, 85.0)

func _pan_camera(relative: Vector2) -> void:
	if relative.length_squared() < 0.5:
		return

	var right = global_transform.basis.x
	var up = global_transform.basis.y
	global_position -= right * relative.x * pan_speed
	global_position += up * relative.y * pan_speed

func _zoom_camera(amount: float) -> void:
	if _camera:
		_camera.position.z += amount
		_camera.position.z = clamp(_camera.position.z, min_zoom, max_zoom)
