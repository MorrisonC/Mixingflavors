extends Node3D
class_name CameraPivotController

## Smooth orbit camera for the 3-D puzzle grid.
## Pixel motion is normalized against a reference viewport so a swipe feels
## consistent on phones and desktop displays.

signal rotation_started
signal rotation_finished
signal view_snapped(face_name: String)

enum SnapFace { FRONT, BACK, LEFT, RIGHT, TOP, BOTTOM }

@export_category("Orbit Settings")
@export var orbit_sensitivity: Vector2 = Vector2(0.015, 0.015)
@export var pitch_min_deg: float = -89.9
@export var pitch_max_deg: float = 89.9
@export var damping_inertia: float = 12.0
@export var reference_viewport_size: Vector2 = Vector2(1280.0, 720.0)
@export var resolution_independent_orbit: bool = true

@export_category("Zoom Settings")
## A grid only a few units from the near plane is difficult to interact with.
@export var min_distance: float = 4.0
@export var max_distance: float = 40.0
@export var minimum_safe_distance: float = 4.0
@export var zoom_sensitivity: float = 1.0
@export var voxel_size: float = 0.9
@export var fit_padding: float = 1.2

@export_category("Node References")
@export var pitch_node: Node3D
@export var camera: Camera3D
@export var spring_arm: SpringArm3D

var target_yaw: float = 0.0
var target_pitch: float = 0.0
var current_yaw: float = 0.0
var current_pitch: float = 0.0
var target_distance: float = 10.0
var current_distance: float = 10.0
var is_rotating: bool = false
var is_tweening: bool = false
var active_tween: Tween


func _ready() -> void:
	if not is_instance_valid(pitch_node):
		pitch_node = $PitchNode as Node3D if has_node("PitchNode") else self
	if not is_instance_valid(camera):
		if is_instance_valid(pitch_node) and pitch_node.has_node("Camera3D"):
			camera = pitch_node.get_node("Camera3D") as Camera3D
		elif is_instance_valid(pitch_node) and pitch_node.has_node("SpringArm3D/Camera3D"):
			camera = pitch_node.get_node("SpringArm3D/Camera3D") as Camera3D
			spring_arm = pitch_node.get_node("SpringArm3D") as SpringArm3D
	if not is_instance_valid(spring_arm) and is_instance_valid(pitch_node) and pitch_node.has_node("SpringArm3D"):
		spring_arm = pitch_node.get_node("SpringArm3D") as SpringArm3D
	current_yaw = rotation.y
	target_yaw = current_yaw
	if is_instance_valid(pitch_node):
		current_pitch = pitch_node.rotation.x
		target_pitch = current_pitch
	if is_instance_valid(spring_arm):
		target_distance = spring_arm.spring_length
	elif is_instance_valid(camera):
		target_distance = camera.position.z
	_clamp_distance_settings()
	target_distance = _clamp_distance(target_distance)
	current_distance = target_distance


func _process(delta: float) -> void:
	_update_camera_aspect()
	if is_tweening:
		return
	var safe_delta: float = maxf(delta, 0.0)
	var blend: float = 1.0 - exp(-maxf(damping_inertia, 0.0) * safe_delta)
	blend = clampf(blend, 0.0, 1.0)
	current_yaw = lerp_angle(current_yaw, target_yaw, blend)
	current_pitch = lerp(current_pitch, target_pitch, blend)
	rotation.y = current_yaw
	if is_instance_valid(pitch_node):
		pitch_node.rotation.x = current_pitch
	target_distance = _clamp_distance(target_distance)
	current_distance = lerp(current_distance, target_distance, blend)
	if is_instance_valid(spring_arm):
		spring_arm.spring_length = current_distance
	elif is_instance_valid(camera):
		camera.position.z = current_distance


func add_orbit_input(relative_motion: Vector2, viewport_size: Vector2 = Vector2.ZERO) -> void:
	if is_tweening or relative_motion.is_zero_approx():
		return
	var scaled_motion: Vector2 = normalized_orbit_delta(relative_motion, viewport_size)
	if not is_rotating:
		is_rotating = true
		rotation_started.emit()
	target_yaw -= scaled_motion.x * orbit_sensitivity.x
	target_pitch -= scaled_motion.y * orbit_sensitivity.y
	target_pitch = clampf(target_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))


func normalized_orbit_delta(relative_motion: Vector2, viewport_size: Vector2 = Vector2.ZERO) -> Vector2:
	if not resolution_independent_orbit:
		return relative_motion
	var actual_size: Vector2 = viewport_size
	if actual_size.x <= 0.0 or actual_size.y <= 0.0:
		actual_size = _viewport_size()
	var reference_size: Vector2 = Vector2(maxf(reference_viewport_size.x, 1.0), maxf(reference_viewport_size.y, 1.0))
	if actual_size.x <= 0.0 or actual_size.y <= 0.0:
		return relative_motion
	return Vector2(relative_motion.x * reference_size.x / actual_size.x, relative_motion.y * reference_size.y / actual_size.y)


func end_orbit() -> void:
	if is_rotating:
		is_rotating = false
		rotation_finished.emit()


func add_zoom_input(amount: float, factor: float = 1.0) -> void:
	if not is_finite(amount) or not is_finite(factor) or factor <= 0.0:
		return
	var effective_amount: float = amount * factor
	if is_finite(effective_amount):
		target_distance = _clamp_distance(target_distance + effective_amount * zoom_sensitivity)


func add_zoom_factor(factor: float) -> void:
	if is_finite(factor) and factor > 0.0:
		target_distance = _clamp_distance(target_distance * factor)


func _orbit_camera(relative_motion: Vector2) -> void:
	add_orbit_input(relative_motion)


func _zoom_camera(amount: float) -> void:
	add_zoom_input(amount)


## Fit a grid whose local origin is its lower corner.  The second argument may
## be a Transform3D; a Vector3 is also accepted as a translation for simple
## callers.
func fit_to_grid(grid_size: Variant, grid_transform: Variant = Transform3D.IDENTITY) -> float:
	var dimensions: Vector3 = _coerce_dimensions(grid_size)
	var transform: Transform3D = _coerce_transform(grid_transform)
	if dimensions.x <= 0.0 or dimensions.y <= 0.0 or dimensions.z <= 0.0 or not _vector_is_finite(dimensions):
		return _current_or_target_distance()
	var local_half_extents: Vector3 = dimensions * maxf(voxel_size, 0.01) * 0.5
	var radius: float = (transform.basis * local_half_extents).length()
	if not is_finite(radius) or radius <= 0.0:
		return _current_or_target_distance()
	var viewport_size: Vector2 = _viewport_size()
	var aspect: float = maxf(viewport_size.x / maxf(viewport_size.y, 0.01), 0.01)
	var vertical_fov: float = deg_to_rad(default_fov_degrees())
	var horizontal_fov: float = 2.0 * atan(tan(vertical_fov * 0.5) * aspect)
	var limiting_fov: float = minf(vertical_fov, horizontal_fov)
	if not is_finite(limiting_fov) or limiting_fov <= 0.0:
		return _current_or_target_distance()
	var required_distance: float = radius / sin(limiting_fov * 0.5) * maxf(fit_padding, 1.0)
	if not is_finite(required_distance):
		return _current_or_target_distance()
	required_distance = maxf(required_distance, _effective_min_distance())
	if required_distance > _effective_max_distance():
		max_distance = required_distance * 1.1
	_clamp_distance_settings()
	target_distance = _clamp_distance(required_distance)
	current_distance = target_distance
	if is_instance_valid(spring_arm):
		spring_arm.spring_length = current_distance
	elif is_instance_valid(camera):
		camera.position.z = current_distance
	return target_distance


func fit_grid_to_view(grid_size: Variant, grid_transform: Variant = Transform3D.IDENTITY) -> float:
	return fit_to_grid(grid_size, grid_transform)


func fit_camera_to_grid(grid_size: Variant, grid_transform: Variant = Transform3D.IDENTITY) -> float:
	return fit_to_grid(grid_size, grid_transform)


func grid_fit(grid_size: Variant, grid_transform: Variant = Transform3D.IDENTITY) -> float:
	return fit_to_grid(grid_size, grid_transform)


## Fit arbitrary world-space bounds; useful when slicing changes the visible
## region without changing the logical grid dimensions.
func fit_to_bounds(min_bounds: Vector3, max_bounds: Vector3) -> float:
	if not _vector_is_finite(min_bounds) or not _vector_is_finite(max_bounds):
		return _current_or_target_distance()
	var min_extent: Vector3 = min_bounds.min(max_bounds)
	var max_extent: Vector3 = min_bounds.max(max_bounds)
	var center: Vector3 = (min_extent + max_extent) * 0.5
	var half_extents: Vector3 = (max_extent - min_extent) * 0.5
	var radius: float = half_extents.length()
	if radius <= 0.0 or not is_finite(radius):
		return _current_or_target_distance()
	var viewport_size: Vector2 = _viewport_size()
	var aspect: float = maxf(viewport_size.x / maxf(viewport_size.y, 0.01), 0.01)
	var fov: float = deg_to_rad(default_fov_degrees())
	var limiting_fov: float = minf(fov, 2.0 * atan(tan(fov * 0.5) * aspect))
	var distance: float = maxf(radius / sin(limiting_fov * 0.5) * maxf(fit_padding, 1.0), _effective_min_distance())
	if distance > _effective_max_distance():
		max_distance = distance * 1.1
	_clamp_distance_settings()
	target_distance = _clamp_distance(distance)
	current_distance = target_distance
	if is_instance_valid(spring_arm):
		spring_arm.spring_length = current_distance
	elif is_instance_valid(camera):
		camera.position.z = current_distance
	if is_inside_tree():
		global_position = center
	else:
		position = center
	return target_distance


func default_fov_degrees() -> float:
	if is_instance_valid(camera) and is_finite(camera.fov) and camera.fov > 0.0 and camera.fov < 179.0:
		return camera.fov
	return 70.0


func _coerce_dimensions(value: Variant) -> Vector3:
	if value is Vector3i:
		return Vector3(value as Vector3i)
	if value is Vector3:
		return value as Vector3
	return Vector3.ZERO


func _coerce_transform(value: Variant) -> Transform3D:
	if value is Transform3D:
		return value as Transform3D
	if value is Vector3:
		return Transform3D(Basis.IDENTITY, value as Vector3)
	return Transform3D.IDENTITY


func _vector_is_finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _viewport_size() -> Vector2:
	if is_inside_tree():
		var viewport: Viewport = get_viewport()
		if is_instance_valid(viewport):
			var size: Vector2 = viewport.get_visible_rect().size
			if size.x > 0.0 and size.y > 0.0:
				return size
	if reference_viewport_size.x > 0.0 and reference_viewport_size.y > 0.0:
		return reference_viewport_size
	return Vector2(1280.0, 720.0)


func _effective_min_distance() -> float:
	return maxf(maxf(min_distance, 0.01), maxf(minimum_safe_distance, 0.01))


func _effective_max_distance() -> float:
	return maxf(max_distance, _effective_min_distance() + 0.01)


func _clamp_distance_settings() -> void:
	min_distance = _effective_min_distance()
	max_distance = _effective_max_distance()


func _clamp_distance(value: float) -> float:
	_clamp_distance_settings()
	return min_distance if not is_finite(value) else clampf(value, min_distance, max_distance)


func _current_or_target_distance() -> float:
	return _clamp_distance(target_distance if is_finite(target_distance) else min_distance)


func _update_camera_aspect() -> void:
	if not is_instance_valid(camera):
		return
	var size: Vector2 = _viewport_size()
	camera.keep_aspect = Camera3D.KEEP_WIDTH if size.y > size.x else Camera3D.KEEP_HEIGHT


func snap_to_face(face: SnapFace, duration: float = 0.3) -> void:
	var new_yaw: float = 0.0
	var new_pitch: float = 0.0
	var face_name: String = ""
	match face:
		SnapFace.FRONT:
			face_name = "Front"
		SnapFace.BACK:
			new_yaw = PI
			face_name = "Back"
		SnapFace.LEFT:
			new_yaw = -PI / 2.0
			face_name = "Left"
		SnapFace.RIGHT:
			new_yaw = PI / 2.0
			face_name = "Right"
		SnapFace.TOP:
			new_yaw = current_yaw
			new_pitch = deg_to_rad(pitch_min_deg)
			face_name = "Top"
		SnapFace.BOTTOM:
			new_yaw = current_yaw
			new_pitch = deg_to_rad(pitch_max_deg)
			face_name = "Bottom"
	if is_instance_valid(active_tween) and active_tween.is_running():
		active_tween.kill()
	is_tweening = true
	target_yaw = new_yaw
	target_pitch = new_pitch
	active_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	active_tween.tween_property(self, "rotation:y", new_yaw, maxf(duration, 0.0))
	if is_instance_valid(pitch_node):
		active_tween.tween_property(pitch_node, "rotation:x", new_pitch, maxf(duration, 0.0))
	active_tween.chain().tween_callback(_finish_snap.bind(new_yaw, new_pitch, face_name))


func _finish_snap(new_yaw: float, new_pitch: float, face_name: String) -> void:
	current_yaw = new_yaw
	target_yaw = new_yaw
	current_pitch = new_pitch
	target_pitch = new_pitch
	is_tweening = false
	view_snapped.emit(face_name)


func recenter_pivot_to_bounds(min_bounds: Vector3, max_bounds: Vector3, duration: float = 0.25) -> void:
	if not _vector_is_finite(min_bounds) or not _vector_is_finite(max_bounds):
		return
	var center_point: Vector3 = (min_bounds + max_bounds) * 0.5
	if not is_inside_tree():
		global_position = center_point
		return
	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", center_point, maxf(duration, 0.0))


func shake(duration: float = 0.2, magnitude: float = 0.1) -> void:
	if not is_inside_tree() or not is_finite(duration) or not is_finite(magnitude):
		return
	var tween: Tween = create_tween()
	var original_pos: Vector3 = position
	var safe_duration: float = maxf(duration, 0.01)
	for index in range(5):
		var offset: Vector3 = Vector3(randf_range(-magnitude, magnitude), randf_range(-magnitude, magnitude), 0.0)
		tween.tween_property(self, "position", original_pos + offset, safe_duration / 10.0)
	tween.tween_property(self, "position", original_pos, safe_duration / 10.0)


func snap_to_top() -> void:
	target_pitch = deg_to_rad(pitch_min_deg)
	target_yaw = 0.0


func snap_to_front() -> void:
	target_pitch = 0.0
	target_yaw = 0.0


func snap_to_side() -> void:
	target_pitch = 0.0
	target_yaw = deg_to_rad(90.0)
