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

func _process(_delta: float) -> void:
	if not _camera:
		return
	var viewport = get_viewport()
	if viewport:
		var size = viewport.get_visible_rect().size
		if size.x < size.y:
			_camera.keep_aspect = Camera3D.KEEP_WIDTH
		else:
			_camera.keep_aspect = Camera3D.KEEP_HEIGHT

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

func shake(duration: float = 0.2, magnitude: float = 0.1) -> void:
	var tween = create_tween()
	var original_pos = position
	for i in range(5):
		var offset = Vector3(
			randf_range(-magnitude, magnitude),
			randf_range(-magnitude, magnitude),
			0
		)
		tween.tween_property(self, "position", original_pos + offset, duration / 10.0)
	tween.tween_property(self, "position", original_pos, duration / 10.0)
