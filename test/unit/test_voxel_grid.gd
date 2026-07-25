extends GutTest

var voxel_grid: VoxelGrid3D
var game_manager: GameManager

func before_each():
    game_manager = GameManager.new()
    GameManager.Instance = game_manager
    add_child(game_manager)
    game_manager.CurrentMode = GameManager.GameMode.Picross3D

    voxel_grid = VoxelGrid3D.new()
    voxel_grid.GridSizeX = 3
    voxel_grid.GridSizeY = 3
    voxel_grid.GridSizeZ = 3
    add_child(voxel_grid)

func after_each():
    voxel_grid.free()
    game_manager.free()
    GameManager.Instance = null

func test_chisel_voxel():
    assert_not_null(voxel_grid._voxelGrid[1][1][1])

    voxel_grid.ChiselVoxel(1, 1, 1)

    # Simulate the queue_free time
    assert_null(voxel_grid._voxelGrid[1][1][1])

func test_add_voxel():
    voxel_grid.ChiselVoxel(1, 1, 1)
    assert_null(voxel_grid._voxelGrid[1][1][1])

    voxel_grid.AddVoxel(1, 1, 1)
    assert_not_null(voxel_grid._voxelGrid[1][1][1])
    assert_true(voxel_grid._voxelGrid[1][1][1] is MeshInstance3D)

func test_apply_alchemy_color():
    game_manager.alchemy_discipline = 2 # Must be > 1

    voxel_grid.ApplyAlchemyColor(0, 0, 0, Color.BLUE)

    var voxel = voxel_grid._voxelGrid[0][0][0]
    var material = voxel.get_surface_override_material(0)

    assert_not_null(material)
    assert_eq(material.albedo_color, Color.BLUE)

func test_corrupted_state_generation():
    game_manager.health = 20 # < 50 triggers corruption

    # Re-generate grid to trigger corruption check
    voxel_grid.GenerateGrid()

    var voxel = voxel_grid._voxelGrid[0][0][0]
    var material = voxel.mesh.material

    assert_not_null(material)
    assert_eq(material.albedo_color, Color.RED)
