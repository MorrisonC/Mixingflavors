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

# Visual properties
var base_material: StandardMaterial3D
var marked_color: Color = Color(0.2, 0.2, 0.8) # Blueish
var highlight_color: Color = Color(1.0, 1.0, 0.2) # Yellowish

func _ready() -> void:
	base_material = StandardMaterial3D.new()
	base_material.albedo_color = Color(1.0, 1.0, 1.0)
	mesh_instance.material_override = base_material

func set_grid_position(pos: Vector3i) -> void:
	grid_position = pos
	position = Vector3(pos.x, pos.y, pos.z)

func set_state(new_state: BlockState) -> void:
	current_state = new_state
	_update_visuals()

func _update_visuals() -> void:
	match current_state:
		BlockState.UNBROKEN:
			show()
			collision_layer = 1
			base_material.albedo_color = Color(1.0, 1.0, 1.0)
		BlockState.MARKED:
			show()
			collision_layer = 1
			base_material.albedo_color = marked_color
		BlockState.DESTROYED:
			hide()
			collision_layer = 0
		BlockState.HIDDEN_BY_SLICE:
			hide()
			collision_layer = 0

func set_highlight(is_highlighted: bool) -> void:
	if current_state == BlockState.UNBROKEN:
		if is_highlighted:
			base_material.albedo_color = highlight_color
			base_material.emission_enabled = true
			base_material.emission = highlight_color
			base_material.emission_energy_multiplier = 0.5
		else:
			base_material.albedo_color = Color(1.0, 1.0, 1.0)
			base_material.emission_enabled = false

# Optional: Adding decals or labels to the block directly if needed,
# though it's often easier to manage them from GridManager.
