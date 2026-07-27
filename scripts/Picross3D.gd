extends Node3D
const GameManagerClass = preload("res://scripts/GameManager.gd")

var grid_size: Vector3i = Vector3i(3, 3, 3)
var voxel_nodes: Dictionary = {}

enum VoxelTargetState {
	EMPTY,
	FILLED
}

enum VoxelPlayerState {
	HIDDEN,
	REMOVED,
	MARKED,
	ERROR
}

var voxel_data: Dictionary = {}
var mistakes: int = 0
var combo: int = 0

signal puzzle_solved
signal mistake_made(total_mistakes)
signal combo_updated(current_combo)

# Slicing bounds
var slice_min: Vector3i = Vector3i(0, 0, 0)
var slice_max: Vector3i = Vector3i(2, 2, 2)

@onready var hints_container: Node3D = Node3D.new()

func _ready() -> void:
	add_child(hints_container)
	slice_max = grid_size - Vector3i(1, 1, 1)
	_generate_solution()
	_build_voxel_grid()
	_generate_hints()
	_update_visibility()

func _generate_solution() -> void:
	# Ensure at least an outer shell or a playable shape. We will randomly assign it for now.
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			for z in range(grid_size.z):
				var pos = Vector3i(x, y, z)
				var is_filled = randf() > 0.4
				voxel_data[pos] = {
					"target": VoxelTargetState.FILLED if is_filled else VoxelTargetState.EMPTY,
					"player": VoxelPlayerState.HIDDEN
				}

func _build_voxel_grid() -> void:
	var is_corrupted = get_node("/root/GameManager").get_stat("health") < 50 or get_node("/root/GameManager").get_stat("endurance") < 50

	for x in range(grid_size.x):
		for y in range(grid_size.y):
			for z in range(grid_size.z):
				var pos = Vector3i(x, y, z)

				var static_body = StaticBody3D.new()
				static_body.position = Vector3(x, y, z) - Vector3(1, 1, 1)
				add_child(static_body)

				var collision_shape = CollisionShape3D.new()
				var box_shape = BoxShape3D.new()
				box_shape.size = Vector3(0.8, 0.8, 0.8)
				collision_shape.shape = box_shape
				static_body.add_child(collision_shape)

				var mesh_instance = MeshInstance3D.new()
				var box = BoxMesh.new()
				box.size = Vector3(0.8, 0.8, 0.8)
				mesh_instance.mesh = box
				static_body.add_child(mesh_instance)

				var mat = StandardMaterial3D.new()
				if is_corrupted:
					mat.albedo_color = Color.RED
				else:
					mat.albedo_color = Color.WHITE
				mesh_instance.material_override = mat

				voxel_nodes[pos] = {
					"body": static_body,
					"mesh": mesh_instance,
					"original_color": mat.albedo_color
				}

				static_body.input_event.connect(_on_voxel_input_event.bind(pos))

func _generate_hints() -> void:
	# Generate hints along the Z axis (looking from front/back)
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			_create_hint_label(Vector3(x, y, grid_size.z), _calculate_line_hint(Vector3i(x, y, 0), Vector3i(0, 0, 1), grid_size.z))

	# X axis (looking from left/right)
	for y in range(grid_size.y):
		for z in range(grid_size.z):
			_create_hint_label(Vector3(grid_size.x, y, z), _calculate_line_hint(Vector3i(0, y, z), Vector3i(1, 0, 0), grid_size.x))

	# Y axis (looking from top/bottom)
	for x in range(grid_size.x):
		for z in range(grid_size.z):
			_create_hint_label(Vector3(x, grid_size.y, z), _calculate_line_hint(Vector3i(x, 0, z), Vector3i(0, 1, 0), grid_size.y))

func _calculate_line_hint(start_pos: Vector3i, step: Vector3i, length: int) -> String:
	var groups = []
	var current_group = 0

	for i in range(length):
		var pos = start_pos + (step * i)
		if voxel_data[pos]["target"] == VoxelTargetState.FILLED:
			current_group += 1
		else:
			if current_group > 0:
				groups.append(current_group)
				current_group = 0

	if current_group > 0:
		groups.append(current_group)

	if groups.size() == 0:
		return "0"
	elif groups.size() == 1:
		return str(groups[0]) # Single block: N
	elif groups.size() == 2:
		return "(" + str(groups[0] + groups[1]) + ")" # Two groups: (N)
	else:
		var total = 0
		for g in groups:
			total += g
		return "[" + str(total) + "]" # Three or more groups: [N]

func _create_hint_label(pos: Vector3, text: String) -> void:
	var label = Label3D.new()
	label.text = text
	label.position = pos - Vector3(1, 1, 1) # Offset based on grid center
	label.pixel_size = 0.05
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hints_container.add_child(label)

func _update_visibility() -> void:
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			for z in range(grid_size.z):
				var pos = Vector3i(x, y, z)
				var node_data = voxel_nodes[pos]

				var is_within_slice = x >= slice_min.x and x <= slice_max.x and y >= slice_min.y and y <= slice_max.y and z >= slice_min.z and z <= slice_max.z

				if is_within_slice and voxel_data[pos]["player"] != VoxelPlayerState.REMOVED:
					node_data["mesh"].visible = true
					node_data["body"].collision_layer = 1
				else:
					node_data["mesh"].visible = false
					node_data["body"].collision_layer = 0

# Allow player to slice layers
func set_slice(min_vec: Vector3i, max_vec: Vector3i) -> void:
	slice_min = min_vec.clamp(Vector3i.ZERO, grid_size - Vector3i.ONE)
	slice_max = max_vec.clamp(Vector3i.ZERO, grid_size - Vector3i.ONE)
	_update_visibility()

func _on_voxel_input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int, pos: Vector3i) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_chisel_voxel(pos)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_mark_voxel(pos)

func _chisel_voxel(pos: Vector3i, is_player_action: bool = true) -> void:
	var data = voxel_data[pos]
	if data["player"] != VoxelPlayerState.HIDDEN:
		return

	if data["target"] == VoxelTargetState.EMPTY:
		# Correct!
		data["player"] = VoxelPlayerState.REMOVED

		if is_player_action:
			combo += 1
			emit_signal("combo_updated", combo)

		_update_visibility()
		_check_win_condition()
	else:
		# Incorrect! Mistake!
		data["player"] = VoxelPlayerState.ERROR
		mistakes += 1

		if is_player_action:
			combo = 0
			emit_signal("combo_updated", combo)

		emit_signal("mistake_made", mistakes)

		# Change material to error state visually
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.BLACK
		var mesh_instance = voxel_nodes[pos]["mesh"]
		mesh_instance.material_override = mat

		var tween = create_tween()
		tween.tween_property(mesh_instance, "scale", Vector3(1.2, 0.8, 1.2), 0.1)
		tween.tween_property(mesh_instance, "scale", Vector3(1.0, 1.0, 1.0), 0.1)

func _mark_voxel(pos: Vector3i) -> void:
	var data = voxel_data[pos]
	if data["player"] == VoxelPlayerState.HIDDEN:
		data["player"] = VoxelPlayerState.MARKED
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.BLUE
		var mesh_instance = voxel_nodes[pos]["mesh"]
		mesh_instance.material_override = mat

		var tween = create_tween()
		tween.tween_property(mesh_instance, "scale", Vector3(0.8, 1.2, 0.8), 0.1)
		tween.tween_property(mesh_instance, "scale", Vector3(1.0, 1.0, 1.0), 0.1)
	elif data["player"] == VoxelPlayerState.MARKED:
		data["player"] = VoxelPlayerState.HIDDEN
		# Revert to exact previous material color
		var mat = StandardMaterial3D.new()
		mat.albedo_color = voxel_nodes[pos]["original_color"]
		var mesh_instance = voxel_nodes[pos]["mesh"]
		mesh_instance.material_override = mat

		var tween = create_tween()
		tween.tween_property(mesh_instance, "scale", Vector3(1.1, 0.9, 1.1), 0.1)
		tween.tween_property(mesh_instance, "scale", Vector3(1.0, 1.0, 1.0), 0.1)

func _check_win_condition() -> void:
	for pos in voxel_data.keys():
		var data = voxel_data[pos]
		if data["target"] == VoxelTargetState.EMPTY and data["player"] != VoxelPlayerState.REMOVED:
			return # Still empty blocks to remove

	emit_signal("puzzle_solved")
	print("[Picross3D] Puzzle Solved!")

func apply_alchemy_color(pos: Vector3i, color: Color) -> void:
	if get_node("/root/GameManager").get_stat("alchemy_discipline") > 1:
		if voxel_nodes.has(pos):
			var mesh_instance = voxel_nodes[pos]["mesh"]
			var mat: StandardMaterial3D = mesh_instance.material_override
			if mat == null:
				mat = StandardMaterial3D.new()
			mat.albedo_color = color
			mesh_instance.material_override = mat
			# update original color for marking/unmarking
			voxel_nodes[pos]["original_color"] = color
			print("[Picross3D] Applied Alchemy color at ", pos)

func _unhandled_input(event: InputEvent) -> void:
	# Debug/Simple slice control mappings
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_X:
			set_slice(slice_min, slice_max - Vector3i(1, 0, 0)) # hide top X layer
		elif event.keycode == KEY_Z:
			set_slice(slice_min, slice_max + Vector3i(1, 0, 0)) # show top X layer
		elif event.keycode == KEY_Y:
			set_slice(slice_min, slice_max - Vector3i(0, 1, 0))
		elif event.keycode == KEY_U:
			set_slice(slice_min, slice_max + Vector3i(0, 1, 0))

func _on_solve_puzzle_pressed() -> void:
	emit_signal("puzzle_solved")
	var payload = {
		"voxel_template": [Vector2(100, 100), Vector2(200, 200)],
		"anchors": [Vector2(150, 300)]
	}
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.MASQUERADE_PAINTING, payload)
