extends Node3D
class_name CameraPivotController

## Signals for UI and Gameplay state synchronization
signal rotation_started
signal rotation_finished
signal view_snapped(face_name: String)

enum SnapFace { FRONT, BACK, LEFT, RIGHT, TOP, BOTTOM }

@export_category("Orbit Settings")
@export var orbit_sensitivity: Vector2 = Vector2(0.015, 0.015)
@export var pitch_min_deg: float = -89.9
@export var pitch_max_deg: float = 89.9
@export var damping_inertia: float = 12.0

@export_category("Zoom Settings")
@export var min_distance: float = 3.0
@export var max_distance: float = 30.0 # Match old max_zoom
@export var zoom_sensitivity: float = 1.0

@export_category("Node References")
@export var pitch_node: Node3D
@export var camera: Camera3D
@export var spring_arm: SpringArm3D

var target_yaw: float = 0.0
var target_pitch: float = 0.0
var current_yaw: float = 0.0
var current_pitch: float = 0.0

var target_distance: float = 10.0
var is_rotating: bool = false
var is_tweening: bool = false
var active_tween: Tween

func _ready() -> void:
	if not pitch_node:
		pitch_node = $PitchNode if has_node("PitchNode") else self
	if not camera and pitch_node.has_node("Camera3D"):
		camera = pitch_node.get_node("Camera3D")
	elif not camera and pitch_node.has_node("SpringArm3D/Camera3D"):
		camera = pitch_node.get_node("SpringArm3D/Camera3D")
		spring_arm = pitch_node.get_node("SpringArm3D")

	if not spring_arm and pitch_node.has_node("SpringArm3D"):
		spring_arm = pitch_node.get_node("SpringArm3D")

	current_yaw = rotation.y
	target_yaw = current_yaw
	if pitch_node:
		current_pitch = pitch_node.rotation.x
		target_pitch = current_pitch

	if spring_arm:
		target_distance = spring_arm.spring_length
	elif camera:
		target_distance = camera.position.z

func _process(delta: float) -> void:
	if camera:
		var viewport = get_viewport()
		if viewport:
			var size = viewport.get_visible_rect().size
			if size.x < size.y:
				camera.keep_aspect = Camera3D.KEEP_WIDTH
			else:
				camera.keep_aspect = Camera3D.KEEP_HEIGHT

	if is_tweening:
		return

	# Smooth rotation interpolation (Damping / Inertia)
	current_yaw = lerp_angle(current_yaw, target_yaw, damping_inertia * delta)
	current_pitch = lerp(current_pitch, target_pitch, damping_inertia * delta)

	rotation.y = current_yaw
	if pitch_node:
		pitch_node.rotation.x = current_pitch

	# Smooth zoom interpolation
	if spring_arm:
		spring_arm.spring_length = lerp(spring_arm.spring_length, target_distance, damping_inertia * delta)
	elif camera:
		camera.position.z = lerp(camera.position.z, target_distance, damping_inertia * delta)

func add_orbit_input(relative_motion: Vector2) -> void:
	if is_tweening:
		return

	if not is_rotating:
		is_rotating = true
		rotation_started.emit()

	target_yaw -= relative_motion.x * orbit_sensitivity.x
	target_pitch -= relative_motion.y * orbit_sensitivity.y
	target_pitch = clamp(target_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))

func end_orbit() -> void:
	if is_rotating:
		is_rotating = false
		rotation_finished.emit()

func add_zoom_input(amount: float) -> void:
	target_distance = clamp(target_distance + (amount * zoom_sensitivity), min_distance, max_distance)

## Snaps camera smoothly to an orthogonal face view (Front, Back, Left, Right, Top, Bottom)
func snap_to_face(face: SnapFace, duration: float = 0.3) -> void:
	var new_yaw: float = 0.0
	var new_pitch: float = 0.0
	var face_name: String = ""

	match face:
		SnapFace.FRONT:
			new_yaw = 0.0
			new_pitch = 0.0
			face_name = "Front"
		SnapFace.BACK:
			new_yaw = PI
			new_pitch = 0.0
			face_name = "Back"
		SnapFace.LEFT:
			new_yaw = -PI / 2.0
			new_pitch = 0.0
			face_name = "Left"
		SnapFace.RIGHT:
			new_yaw = PI / 2.0
			new_pitch = 0.0
			face_name = "Right"
		SnapFace.TOP:
			new_yaw = current_yaw # Preserve horizontal orientation
			new_pitch = deg_to_rad(pitch_min_deg)
			face_name = "Top"
		SnapFace.BOTTOM:
			new_yaw = current_yaw
			new_pitch = deg_to_rad(pitch_max_deg)
			face_name = "Bottom"

	if active_tween and active_tween.is_running():
		active_tween.kill()

	is_tweening = true
	active_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	active_tween.tween_property(self, "rotation:y", new_yaw, duration)
	if pitch_node:
		active_tween.tween_property(pitch_node, "rotation:x", new_pitch, duration)

	active_tween.chain().tween_callback(func():
		current_yaw = new_yaw
		target_yaw = new_yaw
		current_pitch = new_pitch
		target_pitch = new_pitch
		is_tweening = false
		view_snapped.emit(face_name)
	)

## Dynamically recenter pivot point to the middle of visible/active sliced voxels
func recenter_pivot_to_bounds(min_bounds: Vector3, max_bounds: Vector3, duration: float = 0.25) -> void:
	var center_point = (min_bounds + max_bounds) / 2.0
	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", center_point, duration)

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
