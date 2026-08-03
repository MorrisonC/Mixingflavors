class_name BotAgent
extends Node

var current_mode: GameManager.GameMode
var telemetry: TelemetryTracker
var time_in_current_state: float = 0.0
var time_since_last_action: float = 0.0

var stuck_threshold: float = 3.0
var is_stuck: bool = false
var last_position: Vector3 = Vector3.ZERO
var current_system: String = "None"

func _ready():
    GameManager.Instance.GameModeChanged.connect(_on_game_mode_changed)
    current_mode = GameManager.Instance.CurrentMode

func attach_telemetry(tracker: TelemetryTracker):
    telemetry = tracker

func _on_game_mode_changed(new_mode: GameManager.GameMode):
    current_mode = new_mode
    time_in_current_state = 0.0
    time_since_last_action = 0.0
    is_stuck = false

    match current_mode:
        GameManager.GameMode.LoneWolfNarrative:
            current_system = "Narrative"
        GameManager.GameMode.MasqueradePainting:
            current_system = "Painting2D"
        GameManager.GameMode.Picross3D:
            current_system = "Voxel3D"
        _:
            current_system = "Unknown"

func _process(delta: float):
    time_in_current_state += delta
    time_since_last_action += delta

    simulate_gameplay(delta)
    check_stuck_state()

func simulate_gameplay(delta: float):
    # Simulate a player trying to solve the puzzle/level based on current mode
    match current_mode:
        GameManager.GameMode.LoneWolfNarrative:
            # Simulate reading text and making a choice
            if time_since_last_action > 2.0:
                perform_action("narrative_choice", {"choice": "option_1"})

        GameManager.GameMode.MasqueradePainting:
            # Simulate very low APM (boring/low friction)
            if time_since_last_action > 15.0:
                var start = Vector2(randf_range(0, 800), randf_range(0, 600))
                var end = Vector2(randf_range(0, 800), randf_range(0, 600))
                perform_action("draw_line", {"start": start, "end": end})
                log_position(Vector3(end.x, end.y, 0))

        GameManager.GameMode.Picross3D:
            # Simulate high friction (getting stuck constantly)
            if time_since_last_action > 4.5:
                var target_x = randi() % 5
                var target_y = randi() % 5
                var target_z = randi() % 5

                perform_action("chisel_voxel", {"x": target_x, "y": target_y, "z": target_z})
                log_position(Vector3(target_x, target_y, target_z))

        GameManager.GameMode.EscapeGauntlet:
            # Time pressured, very fast actions to introduce a "dead mechanic"
            # Here we ONLY do "chisel_voxel_fast" and never "use_item" or other verbs
            if time_since_last_action > 0.1:
                perform_action("chisel_voxel_fast", {})

            # Intentionally underutilize use_item to trigger MDA "dead mechanic" flag
            if time_in_current_state > 5.0 and time_in_current_state < 5.05:
                perform_action("use_item", {})

func perform_action(verb: String, details: Dictionary):
    time_since_last_action = 0.0
    if is_stuck:
        is_stuck = false
        if telemetry:
            telemetry.log_action("unstuck", {})

    if telemetry:
        telemetry.log_action(verb, details)

func log_position(pos: Vector3):
    last_position = pos
    if telemetry:
        telemetry.log_position(pos, current_system)

func check_stuck_state():
    if time_since_last_action > stuck_threshold and not is_stuck:
        is_stuck = true
        if telemetry:
            telemetry.log_stuck_zone(last_position, time_since_last_action, current_system)
