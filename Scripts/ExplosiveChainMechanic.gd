class_name ExplosiveChainMechanic
extends Node

@export var target_grid: VoxelGrid3D
@export var explosion_radius: int = 1
@export var explosive_positions: Array[Vector3i] = []

# To avoid infinite recursion during chain reactions
var _is_processing_explosion: bool = false
var _voxels_to_explode: Array[Vector3i] = []

func _ready() -> void:
    if target_grid != null:
        target_grid.voxel_chiseled.connect(_on_voxel_chiseled)

func _on_voxel_chiseled(x: int, y: int, z: int) -> void:
    var chiseled_pos = Vector3i(x, y, z)
    if chiseled_pos in explosive_positions:
        # Avoid double-processing if it was already caught in a chain reaction
        if not _is_processing_explosion:
            _trigger_explosion(chiseled_pos)

func _trigger_explosion(origin: Vector3i) -> void:
    _is_processing_explosion = true
    _voxels_to_explode.append(origin)

    # Process explosions in a loop to handle chain reactions iteratively instead of recursively
    while _voxels_to_explode.size() > 0:
        var current_pos = _voxels_to_explode.pop_front()

        # Hazard penalty
        if GameManager.Instance != null:
            GameManager.Instance.health -= 10
            print("Explosive chain mechanic triggered! Health reduced to ", GameManager.Instance.health)

            # Since taking hazard damage should break any combo logic from the player's intentional chiseling:
            if target_grid != null:
                target_grid.current_combo = 0
                target_grid.combo_broken.emit()

        # Remove it from explosive_positions so it doesn't trigger again
        if current_pos in explosive_positions:
            explosive_positions.erase(current_pos)

        # Find all neighbors within radius
        for dx in range(-explosion_radius, explosion_radius + 1):
            for dy in range(-explosion_radius, explosion_radius + 1):
                for dz in range(-explosion_radius, explosion_radius + 1):
                    # Skip the origin itself
                    if dx == 0 and dy == 0 and dz == 0:
                        continue

                    var nx = current_pos.x + dx
                    var ny = current_pos.y + dy
                    var nz = current_pos.z + dz

                    # Only chisel if it's within grid bounds and exists
                    if target_grid != null and nx >= 0 and nx < target_grid.GridSizeX and ny >= 0 and ny < target_grid.GridSizeY and nz >= 0 and nz < target_grid.GridSizeZ:
                        # Check if voxel exists before chiseling
                        var voxel = target_grid._voxelGrid[nx][ny][nz]
                        if voxel != null:
                            # If the neighbor is also explosive, add it to the queue for a chain reaction
                            var neighbor_pos = Vector3i(nx, ny, nz)
                            if neighbor_pos in explosive_positions and not neighbor_pos in _voxels_to_explode:
                                _voxels_to_explode.append(neighbor_pos)

                            # Perform the chisel but flag it as NOT a player action
                            # to avoid combo increments from explosions
                            target_grid.ChiselVoxel(nx, ny, nz, false)

    _is_processing_explosion = false