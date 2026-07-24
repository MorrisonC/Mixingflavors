using Godot;
using System;

namespace HybridTacticalPuzzleRPG
{
    public partial class VoxelGrid3D : Node3D
    {
        [Export]
        public int GridSizeX { get; set; } = 5;
        [Export]
        public int GridSizeY { get; set; } = 5;
        [Export]
        public int GridSizeZ { get; set; } = 5;

        private PackedScene _voxelPrefab;
        private Node3D[,,] _voxelGrid;

        public override void _Ready()
        {
            // Load a generic MeshInstance3D as a fallback if no prefab is assigned,
            // but ideally you'd load the Kenney Voxel Kit scenes here.
            GenerateGrid();
        }

        private void GenerateGrid()
        {
            _voxelGrid = new Node3D[GridSizeX, GridSizeY, GridSizeZ];

            for (int x = 0; x < GridSizeX; x++)
            {
                for (int y = 0; y < GridSizeY; y++)
                {
                    for (int z = 0; z < GridSizeZ; z++)
                    {
                        var meshInstance = new MeshInstance3D();
                        var boxMesh = new BoxMesh();
                        meshInstance.Mesh = boxMesh;

                        // Spread out the grid based on size
                        meshInstance.Position = new Vector3(x - GridSizeX / 2.0f, y - GridSizeY / 2.0f, z - GridSizeZ / 2.0f);

                        // In Godot 4 C# you must use AddChild to add nodes to the tree
                        AddChild(meshInstance);
                        _voxelGrid[x, y, z] = meshInstance;
                    }
                }
            }
        }

        public void ChiselVoxel(int x, int y, int z)
        {
            if (GameManager.Instance.CurrentMode != GameMode.Picross3D) return;

            if (x >= 0 && x < GridSizeX && y >= 0 && y < GridSizeY && z >= 0 && z < GridSizeZ)
            {
                var voxel = _voxelGrid[x, y, z];
                if (voxel != null && voxel.IsInsideTree())
                {
                    // Logic to check if chiseling this block is a valid move based on clues.
                    bool isCorrectMove = true; // Placeholder for actual deduction logic

                    if (isCorrectMove)
                    {
                        voxel.QueueFree();
                        _voxelGrid[x, y, z] = null;
                        CheckPuzzleCompletion();
                    }
                    else
                    {
                        GD.Print("Incorrect chisel!");
                        if (TelemetryService.Instance != null)
                        {
                            TelemetryService.Instance.LogMisclick("Picross3D_Puzzle1");
                        }
                    }
                }
            }
        }

        private void CheckPuzzleCompletion()
        {
            // Placeholder completion check
            bool isComplete = false;
            if (isComplete)
            {
                GD.Print("3D Puzzle Solved!");
                if (TelemetryService.Instance != null)
                {
                    TelemetryService.Instance.LogPuzzleCompletion("Picross3D_Puzzle1", 45.2f, 2);
                }
            }
        }
    }
}
