extends GutTest

var _game_manager: GameManager
var _grid: VoxelGrid3D
var _mechanic: ExplosiveChainMechanic

func before_each():
    _game_manager = GameManager.new()
    add_child_autofree(_game_manager)
    _game_manager._ready()
    # Ensure we are in the correct mode to allow chiseling
    _game_manager.SwitchMode(GameManager.GameMode.Picross3D)

    _grid = VoxelGrid3D.new()
    _grid.GridSizeX = 5
    _grid.GridSizeY = 5
    _grid.GridSizeZ = 5
    add_child_autofree(_grid)
    _grid._ready()

    _mechanic = ExplosiveChainMechanic.new()
    _mechanic.target_grid = _grid
    _mechanic.explosion_radius = 1
    # Add some explosive positions
    _mechanic.explosive_positions = [Vector3i(2, 2, 2), Vector3i(2, 2, 3)]
    add_child_autofree(_mechanic)
    _mechanic._ready()

func test_chiseling_standard_voxel_does_not_trigger_explosion():
    var initial_health = GameManager.Instance.health
    # Chisel a normal voxel
    _grid.ChiselVoxel(0, 0, 0)

    # Assert voxel is gone
    assert_null(_grid._voxelGrid[0][0][0], "Voxel should be removed")

    # Assert health is unchanged
    assert_eq(GameManager.Instance.health, initial_health, "Health should not decrease when chiseling non-explosive voxel")

    # Assert neighbors are not removed
    assert_not_null(_grid._voxelGrid[0][0][1], "Neighboring voxel should not be removed")

func test_chiseling_explosive_voxel_removes_neighbors_and_reduces_health():
    var initial_health = GameManager.Instance.health

    # Assert neighbor is present
    assert_not_null(_grid._voxelGrid[1][1][1], "Neighbor should exist before explosion")

    # Chisel an explosive voxel
    _grid.ChiselVoxel(2, 2, 2)

    # Assert voxel is gone
    assert_null(_grid._voxelGrid[2][2][2], "Explosive voxel should be removed")

    # Since (2,2,3) is also explosive, it will trigger a chain reaction, leading to 2 explosions
    # Initial health 100 - 10 - 10 = 80
    assert_eq(GameManager.Instance.health, initial_health - 20, "Health should be reduced twice due to chain reaction")

    # Verify neighbors within radius 1 are removed
    assert_null(_grid._voxelGrid[1][1][1], "Neighboring voxel (radius 1) should be removed")
    assert_null(_grid._voxelGrid[3][3][3], "Neighboring voxel (radius 1) should be removed")

    # Verify a voxel outside the radius (for both 2,2,2 and 2,2,3 the max reach is 3) remains
    # 0,0,0 is distance > 1 from both
    assert_not_null(_grid._voxelGrid[0][0][0], "Distant voxel should not be removed")