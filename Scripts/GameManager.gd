class_name GameManager
extends Node

enum GameMode {
    LoneWolfNarrative,
    MasqueradePainting,
    Picross3D,
    DetectiveCrimeScene,
    EscapeGauntlet,
    TimeShiftPalimpsest
}

static var Instance: GameManager

var CurrentMode: GameMode = GameMode.LoneWolfNarrative

# RPG Stats & Modifiers
var perception_level: int = 1
var health: int = 100
var endurance: int = 100
var lore_discipline: int = 1
var alchemy_discipline: int = 2

signal GameModeChanged(newMode)

func _enter_tree() -> void:
    if Instance == null:
        Instance = self
    else:
        queue_free()

func _ready() -> void:
    print("GameManager initialized.")
    SwitchMode(GameMode.LoneWolfNarrative)

func SwitchMode(newMode: GameMode) -> void:
    if CurrentMode == newMode:
        return

    print("Switching game mode from ", CurrentMode, " to ", newMode)
    CurrentMode = newMode

    # Logic to disable/enable relevant UI and nodes for the new mode
    match newMode:
        GameMode.LoneWolfNarrative:
            # Enable Node-based narrative UI, Disable 3D/Painting Canvas
            pass
        GameMode.MasqueradePainting:
            # Enable 2D Canvas drawing, Disable 3D/Narrative UI
            pass
        GameMode.Picross3D:
            # Enable 3D Voxel Grid, Disable 2D/Narrative UI
            pass
        GameMode.DetectiveCrimeScene:
            # Enable non-linear 3D/2D exploration
            pass
        GameMode.EscapeGauntlet:
            # Enable time-pressured Voxel puzzles
            pass
        GameMode.TimeShiftPalimpsest:
            # Enable 2D past/present overlays
            pass

    GameModeChanged.emit(newMode)

    # Log mode switch telemetry
    if TelemetryService.Instance != null:
        TelemetryService.Instance.LogNarrativeEvent("ModeSwitched_" + str(newMode), "System")
