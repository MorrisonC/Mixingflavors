extends Node3D

var grid_size: Vector3i = Vector3i(3, 3, 3)
var voxel_nodes: Dictionary = {}

func _ready() -> void:
	_build_voxel_grid()

func _build_voxel_grid() -> void:
	var is_corrupted = GameManager.get_stat("health") < 50 or GameManager.get_stat("endurance") < 50

	for x in range(grid_size.x):
		for y in range(grid_size.y):
			for z in range(grid_size.z):
				var mesh_instance = MeshInstance3D.new()
				var box = BoxMesh.new()
				box.size = Vector3(0.8, 0.8, 0.8)
				mesh_instance.mesh = box

				var mat = StandardMaterial3D.new()
				if is_corrupted:
					mat.albedo_color = Color.RED # Voxels turn red when health/endurance is low
				else:
					mat.albedo_color = Color.WHITE

				mesh_instance.material_override = mat
				mesh_instance.position = Vector3(x, y, z) - Vector3(1, 1, 1)

				add_child(mesh_instance)
				voxel_nodes[Vector3i(x, y, z)] = mesh_instance

func apply_alchemy_color(pos: Vector3i, color: Color) -> void:
	if GameManager.get_stat("alchemy_discipline") > 1:
		if voxel_nodes.has(pos):
			var mat: StandardMaterial3D = voxel_nodes[pos].material_override
			mat.albedo_color = color
			print("[Picross3D] Applied Alchemy color at ", pos)

func _on_solve_puzzle_pressed() -> void:
	# Pass solved state back to MasqueradePainting
	var payload = {
		"voxel_template": [Vector2(100, 100), Vector2(200, 200)],
		"anchors": [Vector2(150, 300)]
	}
	GameManager.switch_mode(GameManager.GameMode.MASQUERADE_PAINTING, payload)
