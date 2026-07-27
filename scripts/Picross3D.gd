extends Node3D

var grid_size: Vector3i = Vector3i(3, 3, 3)
var voxel_nodes: Dictionary = {}
var camera: Camera3D

func _ready() -> void:
    _build_voxel_grid()
    camera = get_viewport().get_camera_3d()

func _build_voxel_grid() -> void:
    var is_corrupted = GameManager.get_stat("health") < 50 or GameManager.get_stat("endurance") < 50

    var parent = Node3D.new()
    add_child(parent)

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

                var collision_shape = CollisionShape3D.new()
                var box_shape = BoxShape3D.new()
                box_shape.size = box.size
                collision_shape.shape = box_shape

                var static_body = StaticBody3D.new()
                static_body.add_child(collision_shape)
                mesh_instance.add_child(static_body)

                parent.add_child(mesh_instance)
                voxel_nodes[Vector3i(x, y, z)] = mesh_instance

func apply_alchemy_color(pos: Vector3i, color: Color) -> void:
    if GameManager.get_stat("alchemy_discipline") > 1:
        if voxel_nodes.has(pos):
            var mat: StandardMaterial3D = voxel_nodes[pos].material_override
            mat.albedo_color = color
            print("[Picross3D] Applied Alchemy color at ", pos)

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if camera == null:
            camera = get_viewport().get_camera_3d()
        if camera == null:
            return

        var from = camera.project_ray_origin(event.position)
        var to = from + camera.project_ray_normal(event.position) * 1000.0

        var space_state = get_world_3d().direct_space_state
        var query = PhysicsRayQueryParameters3D.create(from, to)
        var result = space_state.intersect_ray(query)

        if result:
            var clicked_mesh = result.collider.get_parent()
            if clicked_mesh is MeshInstance3D:
                clicked_mesh.queue_free()

                # Cleanup dictionary (optional but good practice)
                for key in voxel_nodes:
                    if voxel_nodes[key] == clicked_mesh:
                        voxel_nodes.erase(key)
                        break

func _on_solve_puzzle_pressed() -> void:
    # Pass solved state back to MasqueradePainting
    var payload = {
        "voxel_template": [Vector2(100, 100), Vector2(200, 200)],
        "anchors": [Vector2(150, 300)]
    }
    GameManager.switch_mode(GameManager.GameMode.MASQUERADE_PAINTING, payload)
