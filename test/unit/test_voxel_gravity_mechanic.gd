extends GutTest

var GameManagerObj = load("res://Scripts/GameManager.gd")
var VoxelGrid3DObj = load("res://Scripts/VoxelGrid3D.gd")
var VoxelGravityMechanicObj = load("res://Scripts/VoxelGravityMechanic.gd")

var game_manager: GameManager
var grid: VoxelGrid3D
var gravity_mechanic: VoxelGravityMechanic

func before_each():
    game_manager = GameManagerObj.new()
    add_child_autofree(game_manager)
    game_manager.SwitchMode(GameManager.GameMode.Picross3D)

    grid = VoxelGrid3DObj.new()
    grid.GridSizeX = 3
    grid.GridSizeY = 3
    grid.GridSizeZ = 3
    add_child_autofree(grid)

    gravity_mechanic = VoxelGravityMechanicObj.new()
    gravity_mechanic.target_grid = grid
    add_child_autofree(gravity_mechanic)

func after_each():
    pass

func test_gravity_shifts_voxel_down():
    # Make sure the grid generates
    grid.GenerateGrid()

    # Wait one frame to ensure nodes are completely in tree
    await get_tree().process_frame

    # Store references to the voxels
    var voxel_above = grid._voxelGrid[1][1][1]
    var voxel_top = grid._voxelGrid[1][2][1]

    # Chisel the one below
    grid.ChiselVoxel(1, 0, 1)

    # The signal voxel_chiseled is emitted synchronously from ChiselVoxel in VoxelGrid3D.gd.
    await get_tree().process_frame

    # Assert the one above shifted down
    assert_eq(grid._voxelGrid[1][0][1], voxel_above, "Voxel at y=1 should have shifted down to y=0")

    # Assert the one at the top shifted down
    assert_eq(grid._voxelGrid[1][1][1], voxel_top, "Voxel at y=2 should have shifted down to y=1")

    # The original top position should be null
    assert_null(grid._voxelGrid[1][2][1], "Original top position should be null")

func test_gravity_disabled():
    grid.GenerateGrid()
    gravity_mechanic.gravity_enabled = false

    await get_tree().process_frame

    var voxel_above = grid._voxelGrid[1][1][1]

    grid.ChiselVoxel(1, 0, 1)

    await get_tree().process_frame

    assert_null(grid._voxelGrid[1][0][1], "Chiseled voxel should be null")
    assert_eq(grid._voxelGrid[1][1][1], voxel_above, "Voxel should NOT have shifted down")

func test_core_functionality_unaffected():
    # Disconnect the signal to simulate core functionality without the mechanic
    if gravity_mechanic.target_grid.voxel_chiseled.is_connected(gravity_mechanic._on_voxel_chiseled):
        gravity_mechanic.target_grid.voxel_chiseled.disconnect(gravity_mechanic._on_voxel_chiseled)

    grid.GenerateGrid()

    await get_tree().process_frame

    var voxel_above = grid._voxelGrid[1][1][1]

    grid.ChiselVoxel(1, 0, 1)

    await get_tree().process_frame

    assert_null(grid._voxelGrid[1][0][1], "Chiseled voxel should be null")
    assert_eq(grid._voxelGrid[1][1][1], voxel_above, "Voxel should NOT have shifted down")
