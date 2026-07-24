using Godot;
using System;

namespace HybridTacticalPuzzleRPG
{
    public enum GameMode
    {
        LoneWolfNarrative,
        MasqueradePainting,
        Picross3D
    }

    public partial class GameManager : Node
    {
        public static GameManager Instance { get; private set; }

        public GameMode CurrentMode { get; private set; } = GameMode.LoneWolfNarrative;

        [Signal]
        public delegate void GameModeChangedEventHandler(GameMode newMode);

        public override void _EnterTree()
        {
            if (Instance == null)
            {
                Instance = this;
            }
            else
            {
                QueueFree();
            }
        }

        public override void _Ready()
        {
            GD.Print("GameManager initialized.");
            SwitchMode(GameMode.LoneWolfNarrative);
        }

        public void SwitchMode(GameMode newMode)
        {
            if (CurrentMode == newMode) return;

            GD.Print($"Switching game mode from {CurrentMode} to {newMode}");
            CurrentMode = newMode;

            // Logic to disable/enable relevant UI and nodes for the new mode
            switch (newMode)
            {
                case GameMode.LoneWolfNarrative:
                    // Enable Node-based narrative UI, Disable 3D/Painting Canvas
                    break;
                case GameMode.MasqueradePainting:
                    // Enable 2D Canvas drawing, Disable 3D/Narrative UI
                    break;
                case GameMode.Picross3D:
                    // Enable 3D Voxel Grid, Disable 2D/Narrative UI
                    break;
            }

            EmitSignal(SignalName.GameModeChanged, Variant.From(newMode));

            // Log mode switch telemetry
            if (TelemetryService.Instance != null)
            {
                TelemetryService.Instance.LogNarrativeEvent($"ModeSwitched_{newMode}", "System");
            }
        }
    }
}
