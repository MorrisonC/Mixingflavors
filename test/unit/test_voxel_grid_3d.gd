extends GutTest

func test_generate_grid():
    var voxel_grid = VoxelGrid3D.new()

    # Setup custom grid size for test to avoid default 5x5x5 and ensure logic handles arbitrary dimensions
    voxel_grid.GridSizeX = 3
    voxel_grid.GridSizeY = 2
    voxel_grid.GridSizeZ = 4

    # Generate the grid manually (not adding to tree to avoid _ready running default generation)
    voxel_grid.GenerateGrid()

    # 1. Verify array dimensions
    assert_eq(voxel_grid._voxelGrid.size(), 3, "X dimension should be 3")
    assert_eq(voxel_grid._voxelGrid[0].size(), 2, "Y dimension should be 2")
    assert_eq(voxel_grid._voxelGrid[0][0].size(), 4, "Z dimension should be 4")

    # 2. Verify number of children added
    var expected_children = 3 * 2 * 4
    assert_eq(voxel_grid.get_child_count(), expected_children, "Should have 24 child nodes")

    # 3. Verify specific voxel positions and types
    for x in range(3):
        for y in range(2):
            for z in range(4):
                var voxel = voxel_grid._voxelGrid[x][y][z]
                assert_not_null(voxel, "Voxel should not be null")
                assert_true(voxel is MeshInstance3D, "Voxel should be a MeshInstance3D")

                var expected_pos = Vector3(x - 3 / 2.0, y - 2 / 2.0, z - 4 / 2.0)
                assert_eq(voxel.position, expected_pos, "Voxel position should match generation logic")

    voxel_grid.free()
