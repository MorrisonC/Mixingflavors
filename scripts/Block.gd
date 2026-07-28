extends StaticBody3D

class_name PicrossBlock

enum BlockState {
	UNBROKEN,
	MARKED,
	DESTROYED,
	HIDDEN_BY_SLICE
}

var current_state: BlockState = BlockState.UNBROKEN
var grid_position: Vector3i

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var break_particles: GPUParticles3D = get_node_or_null("BreakParticles")

# Visual properties
var base_material: StandardMaterial3D
var outline_material: ShaderMaterial
var marked_color: Color = Color(0.2, 0.2, 0.8) # Blueish
var highlight_color: Color = Color(1.0, 1.0, 0.2) # Yellowish

func _ready() -> void:
	base_material = StandardMaterial3D.new()
	base_material.albedo_color = Color(1.0, 1.0, 1.0)

	# Add stylized bevels (if supported by standard material, otherwise just clean color)
	base_material.roughness = 0.4

	outline_material = ShaderMaterial.new()
	var shader = load("res://scenes/VoxelOutline.gdshader")
	if shader:
		outline_material.shader = shader
		outline_material.set_shader_parameter("outline_color", highlight_color)
		outline_material.set_shader_parameter("outline_width", 0.03)

	mesh_instance.material_override = base_material

func set_grid_position(pos: Vector3i) -> void:
	grid_position = pos
	position = Vector3(pos.x, pos.y, pos.z)

func set_state(new_state: BlockState) -> void:
	if current_state == BlockState.UNBROKEN and new_state == BlockState.DESTROYED:
		if break_particles:
			break_particles.restart()

	if new_state == BlockState.MARKED or (current_state == BlockState.MARKED and new_state == BlockState.UNBROKEN):
		_play_juice_tween()

	current_state = new_state
	_update_visuals()

func _play_juice_tween() -> void:
	if mesh_instance:
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_SPRING)
		tween.set_ease(Tween.EASE_OUT)
		# Squash
		tween.tween_property(mesh_instance, "scale", Vector3(1.2, 0.8, 1.2), 0.05)
		# Stretch
		tween.tween_property(mesh_instance, "scale", Vector3(0.9, 1.1, 0.9), 0.1)
		# Settle
		tween.tween_property(mesh_instance, "scale", Vector3(1.0, 1.0, 1.0), 0.1)

func _update_visuals() -> void:
	match current_state:
		BlockState.UNBROKEN:
			show()
			mesh_instance.show()
			collision_layer = 1
			base_material.albedo_color = Color(1.0, 1.0, 1.0)
		BlockState.MARKED:
			show()
			mesh_instance.show()
			collision_layer = 1
			base_material.albedo_color = marked_color
		BlockState.DESTROYED:
			mesh_instance.hide()
			collision_layer = 0
		BlockState.HIDDEN_BY_SLICE:
			hide()
			collision_layer = 0

func set_highlight(is_highlighted: bool) -> void:
	if current_state == BlockState.UNBROKEN:
		if is_highlighted:
			if outline_material.shader:
				base_material.next_pass = outline_material
			else:
				# Fallback if shader is missing
				base_material.emission_enabled = true
				base_material.emission = highlight_color
				base_material.emission_energy_multiplier = 0.5
		else:
			base_material.next_pass = null
			base_material.emission_enabled = false

# Optional: Adding decals or labels to the block directly if needed,
# though it's often easier to manage them from GridManager.
