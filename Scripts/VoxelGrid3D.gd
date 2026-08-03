class_name VoxelGrid3D
extends Node3D

signal voxel_chiseled(x: int, y: int, z: int)
signal combo_updated(new_combo: int)
signal combo_broken()

@export var GridSizeX: int = 4
@export var GridSizeY: int = 4
@export var GridSizeZ: int = 4
@export var combo_timeout: float = 3.0

var _voxelGrid: Array = []
var current_combo: int = 0
var combo_timer: float = 0.0

func _process(delta: float) -> void:
    if current_combo > 0:
        combo_timer -= delta
        if combo_timer <= 0.0:
            current_combo = 0
            combo_broken.emit()

func _ready() -> void:
    # Load a generic MeshInstance3D as a fallback if no prefab is assigned,
    # but ideally you'd load the Kenney Voxel Kit scenes here.
    GenerateGrid()

func GenerateGrid() -> void:
    _voxelGrid.resize(GridSizeX)
    for x in range(GridSizeX):
        _voxelGrid[x] = []
        _voxelGrid[x].resize(GridSizeY)
        for y in range(GridSizeY):
            _voxelGrid[x][y] = []
            _voxelGrid[x][y].resize(GridSizeZ)
            for z in range(GridSizeZ):
                var meshInstance = MeshInstance3D.new()
                var boxMesh = BoxMesh.new()
                meshInstance.mesh = boxMesh

                # Check for corrupted state
                if GameManager.Instance != null and (GameManager.Instance.health < 50 or GameManager.Instance.endurance < 50):
                    var material = StandardMaterial3D.new()
                    material.albedo_color = Color.RED
                    boxMesh.material = material

                # Spread out the grid based on size
                meshInstance.position = Vector3(x - GridSizeX / 2.0, y - GridSizeY / 2.0, z - GridSizeZ / 2.0)

                add_child(meshInstance)
                _voxelGrid[x][y][z] = meshInstance

func ChiselVoxel(x: int, y: int, z: int, is_player_action: bool = true) -> void:
    if GameManager.Instance.CurrentMode != GameManager.GameMode.Picross3D:
        return

    if x >= 0 and x < GridSizeX and y >= 0 and y < GridSizeY and z >= 0 and z < GridSizeZ:
        var voxel = _voxelGrid[x][y][z]
        if voxel != null and voxel.is_inside_tree():
            # Logic to check if chiseling this block is a valid move based on clues.
            var isCorrectMove: bool = true # Placeholder for actual deduction logic

            if isCorrectMove:
                _voxelGrid[x][y][z] = null

                if is_player_action:
                    current_combo += 1
                    combo_timer = combo_timeout
                    combo_updated.emit(current_combo)

                    if current_combo % 5 == 0 and GameManager.Instance != null:
                        GameManager.Instance.health = min(GameManager.Instance.health + 5, 100)

                # Add juice: animate scale down before freeing
                var tween = create_tween()
                tween.tween_property(voxel, "scale", Vector3.ZERO, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
                tween.tween_callback(voxel.queue_free)

                CheckPuzzleCompletion()
                voxel_chiseled.emit(x, y, z)
            else:
                if is_player_action:
                    current_combo = 0
                    combo_broken.emit()
                print("Incorrect chisel!")
                if TelemetryService.Instance != null:
                    TelemetryService.Instance.LogMisclick("Picross3D_Puzzle1")

func AddVoxel(x: int, y: int, z: int) -> void:
    if GameManager.Instance.CurrentMode != GameManager.GameMode.Picross3D:
        return

    if x >= 0 and x < GridSizeX and y >= 0 and y < GridSizeY and z >= 0 and z < GridSizeZ:
        if _voxelGrid[x][y][z] == null:
            var meshInstance = MeshInstance3D.new()
            var boxMesh = BoxMesh.new()
            meshInstance.mesh = boxMesh
            meshInstance.position = Vector3(x - GridSizeX / 2.0, y - GridSizeY / 2.0, z - GridSizeZ / 2.0)

            # Add visual juice: scale up from zero
            meshInstance.scale = Vector3.ZERO
            add_child(meshInstance)

            var tween = create_tween()
            tween.tween_property(meshInstance, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

            _voxelGrid[x][y][z] = meshInstance
            CheckPuzzleCompletion()

func ApplyAlchemyColor(x: int, y: int, z: int, color: Color) -> void:
    if GameManager.Instance.CurrentMode != GameManager.GameMode.Picross3D:
        return

    if GameManager.Instance.alchemy_discipline > 1:
        if x >= 0 and x < GridSizeX and y >= 0 and y < GridSizeY and z >= 0 and z < GridSizeZ:
            var voxel = _voxelGrid[x][y][z]
            if voxel != null and voxel.is_inside_tree() and voxel is MeshInstance3D:
                var material = StandardMaterial3D.new()
                material.albedo_color = color
                voxel.set_surface_override_material(0, material)

func CheckPuzzleCompletion() -> void:
    # Placeholder completion check
    var isComplete: bool = false
    if isComplete:
        print("3D Puzzle Solved!")

        # Simulate passing template to 2D canvas
        var canvas = get_node_or_null("/root/PaintingCanvas2D")
        if canvas != null and canvas.has_method("RegisterVoxelTemplate"):
            var new_anchors: Array[Vector2] = [Vector2(50, 50), Vector2(150, 150)]
            canvas.RegisterVoxelTemplate(new_anchors)

        if TelemetryService.Instance != null:
            TelemetryService.Instance.LogPuzzleCompletion("Picross3D_Puzzle1", 45.2, 2)
