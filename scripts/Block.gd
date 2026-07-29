extends StaticBody3D

class_name VoxelBlock

enum BlockState {
	UNBROKEN,
	MARKED,
	PAINTED,
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
var marked_color: Color = Color(0.18, 0.55, 0.85) # Nice Blue/Cyan for marked (nathsou's style)
var painted_color: Color = Color(0.18, 0.55, 0.85) # Keep simple: marked and painted both show as blue/kept block
var highlight_color: Color = Color(1.0, 0.7, 0.1) # Bold orange highlight for hovered outlines
var outline_default_color: Color = Color(0.0, 0.0, 0.0) # Bold black outlines by default
var default_color: Color = Color(1.0, 1.0, 1.0) # Solid clean white blocks (nathsou's style)

# Face elements mapped by direction Vector3i
var face_labels: Dictionary = {}
var face_sprites: Dictionary = {}

# Hint textures generated dynamically
static var circle_texture: ImageTexture
static var square_texture: ImageTexture

static func _init_textures() -> void:
	if circle_texture != null:
		return
	
	# Generate Circle Texture
	var c_img = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	c_img.fill(Color(0, 0, 0, 0))
	var center = Vector2(64, 64)
	var radius = 48.0
	for y in range(128):
		for x in range(128):
			var dist = center.distance_to(Vector2(x, y))
			if abs(dist - radius) < 3.0:
				c_img.set_pixel(x, y, Color(0, 0, 0, 1)) # Bold black outline
	circle_texture = ImageTexture.create_from_image(c_img)
	
	# Generate Square Texture
	var s_img = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	s_img.fill(Color(0, 0, 0, 0))
	var border = 16
	for y in range(128):
		for x in range(128):
			if x >= border and x <= 128 - border and y >= border and y <= 128 - border:
				if x < border + 6 or x > 128 - border - 6 or y < border + 6 or y > 128 - border - 6:
					s_img.set_pixel(x, y, Color(0, 0, 0, 1))
	square_texture = ImageTexture.create_from_image(s_img)

func _ready() -> void:
	_init_textures()

	base_material = StandardMaterial3D.new()
	base_material.albedo_color = default_color
	base_material.roughness = 0.8 # Less shiny, more clay-like

	outline_material = ShaderMaterial.new()
	var shader = load("res://scenes/VoxelOutline.gdshader")
	if shader:
		outline_material.shader = shader
		outline_material.set_shader_parameter("outline_color", outline_default_color)
		outline_material.set_shader_parameter("outline_width", 0.02) # Bold crisp outlines
	
	base_material.next_pass = outline_material
	mesh_instance.material_override = base_material
	_create_face_labels()

func _create_face_labels() -> void:
	var directions = [
		{"dir": Vector3i(1, 0, 0), "pos": Vector3(0.501, 0, 0), "rot": Vector3(0, 90, 0)},
		{"dir": Vector3i(-1, 0, 0), "pos": Vector3(-0.501, 0, 0), "rot": Vector3(0, -90, 0)},
		{"dir": Vector3i(0, 1, 0), "pos": Vector3(0, 0.501, 0), "rot": Vector3(-90, 0, 0)},
		{"dir": Vector3i(0, -1, 0), "pos": Vector3(0, -0.501, 0), "rot": Vector3(90, 0, 0)},
		{"dir": Vector3i(0, 0, 1), "pos": Vector3(0, 0, 0.501), "rot": Vector3(0, 0, 0)},
		{"dir": Vector3i(0, 0, -1), "pos": Vector3(0, 0, -0.501), "rot": Vector3(0, 180, 0)}
	]

	for d in directions:
		# Sprite for Circle/Square backgrounds
		var sprite = Sprite3D.new()
		sprite.position = d["pos"]
		sprite.rotation = Vector3(deg_to_rad(d["rot"].x), deg_to_rad(d["rot"].y), deg_to_rad(d["rot"].z))
		sprite.pixel_size = 0.007
		sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sprite.double_sided = false
		sprite.visible = false
		add_child(sprite)
		face_sprites[d["dir"]] = sprite

		# Label for number
		var label = Label3D.new()
		label.text = ""
		# Position slightly in front of the sprite to avoid z-fighting
		label.position = d["pos"] + d["dir"] * 0.002
		label.rotation = Vector3(deg_to_rad(d["rot"].x), deg_to_rad(d["rot"].y), deg_to_rad(d["rot"].z))
		label.pixel_size = 0.007
		label.font_size = 72
		label.outline_size = 0 # No outlines for clean bold nathsou look
		label.modulate = Color(0, 0, 0) # Pitch black text
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.double_sided = false
		label.visible = false
		add_child(label)
		face_labels[d["dir"]] = label

func set_face_hint(direction: Vector3i, hint_text: String) -> void:
	# Parse simple text back to structured data for compatibility
	var num = hint_text.to_int()
	var type = 0
	if hint_text.begins_with("("):
		type = 1
	elif hint_text.begins_with("["):
		type = 2
	
	set_face_hint_data(direction, {"num": num, "type": type})

func set_face_hint_data(direction: Vector3i, hint_data: Dictionary) -> void:
	if face_labels.has(direction) and face_sprites.has(direction):
		var label = face_labels[direction] as Label3D
		var sprite = face_sprites[direction] as Sprite3D
		
		if hint_data.is_empty() or hint_data["num"] == 0:
			label.visible = false
			sprite.visible = false
			label.text = ""
		else:
			label.text = str(hint_data["num"])
			
			var is_visible = (current_state != BlockState.DESTROYED and current_state != BlockState.HIDDEN_BY_SLICE)
			label.visible = is_visible
			
			if hint_data["type"] == 1:
				sprite.texture = circle_texture
				sprite.visible = is_visible
			elif hint_data["type"] == 2:
				sprite.texture = square_texture
				sprite.visible = is_visible
			else:
				sprite.visible = false

func clear_all_hints() -> void:
	for dir in face_labels.keys():
		face_labels[dir].visible = false
		face_sprites[dir].visible = false

func set_grid_position(pos: Vector3i) -> void:
	grid_position = pos
	position = Vector3(pos.x, pos.y, pos.z)

func set_state(new_state: BlockState) -> void:
	if current_state == BlockState.UNBROKEN and new_state == BlockState.DESTROYED:
		if break_particles:
			break_particles.restart()
	current_state = new_state
	_update_visuals()

func _update_visuals() -> void:
	match current_state:
		BlockState.UNBROKEN:
			show()
			mesh_instance.show()
			collision_layer = 1
			base_material.albedo_color = default_color
			for dir in face_labels.keys():
				if face_labels[dir].text != "":
					face_labels[dir].visible = true
					# Only show circular/squared backdrops if correct type
					var label_text = face_labels[dir].text
					var sprite = face_sprites[dir]
					if sprite.texture != null:
						sprite.visible = true
		BlockState.MARKED, BlockState.PAINTED:
			show()
			mesh_instance.show()
			collision_layer = 1
			base_material.albedo_color = marked_color
			for dir in face_labels.keys():
				if face_labels[dir].text != "":
					face_labels[dir].visible = true
					var sprite = face_sprites[dir]
					if sprite.texture != null:
						sprite.visible = true
		BlockState.DESTROYED:
			mesh_instance.hide()
			collision_layer = 0
			for dir in face_labels.keys():
				face_labels[dir].visible = false
				face_sprites[dir].visible = false
		BlockState.HIDDEN_BY_SLICE:
			hide()
			collision_layer = 0
			for dir in face_labels.keys():
				face_labels[dir].visible = false
				face_sprites[dir].visible = false

func set_highlight(is_highlighted: bool) -> void:
	if current_state != BlockState.DESTROYED and current_state != BlockState.HIDDEN_BY_SLICE:
		if is_highlighted:
			outline_material.set_shader_parameter("outline_color", highlight_color)
			outline_material.set_shader_parameter("outline_width", 0.04) # Thicker highlight
		else:
			outline_material.set_shader_parameter("outline_color", outline_default_color)
			outline_material.set_shader_parameter("outline_width", 0.02) # Standard outline

func disable_outline() -> void:
	if outline_material:
		outline_material.set_shader_parameter("outline_width", 0.0)

func play_interaction_juice() -> void:
	if not mesh_instance:
		return

	var tween = create_tween()
	# Squash and stretch effect
	tween.tween_property(mesh_instance, "scale", Vector3(1.2, 0.8, 1.2), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mesh_instance, "scale", Vector3(0.9, 1.1, 0.9), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(mesh_instance, "scale", Vector3.ONE, 0.08).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
