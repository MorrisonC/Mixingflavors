class_name VoxelGravityMechanic
extends Node

@export var target_grid: VoxelGrid3D
@export var gravity_enabled: bool = true
@export var gravity_delay: float = 0.15

func _ready() -> void:
    if target_grid != null:
        target_grid.voxel_chiseled.connect(_on_voxel_chiseled)

func _on_voxel_chiseled(x: int, y: int, z: int) -> void:
    if not gravity_enabled or target_grid == null:
        return

    _apply_gravity(x, y, z)

func _apply_gravity(chiseled_x: int, chiseled_y: int, chiseled_z: int) -> void:
    if target_grid == null:
        return

    var grid = target_grid._voxelGrid
    var size_y = target_grid.GridSizeY

    for current_y in range(chiseled_y + 1, size_y):
        var voxel = grid[chiseled_x][current_y][chiseled_z]
        if voxel != null:
            # Shift the voxel down in the logic grid
            grid[chiseled_x][current_y - 1][chiseled_z] = voxel
            grid[chiseled_x][current_y][chiseled_z] = null

            # Animate the voxel moving down visually
            var target_pos = Vector3(chiseled_x - target_grid.GridSizeX / 2.0, (current_y - 1) - size_y / 2.0, chiseled_z - target_grid.GridSizeZ / 2.0)

            # Only tween if it's inside the tree
            if is_inside_tree() and voxel.is_inside_tree():
                var tween = create_tween()
                tween.tween_interval(gravity_delay)
                tween.tween_property(voxel, "position", target_pos, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
            else:
                voxel.position = target_pos
