class_name BotAgent
extends Node

const GameManagerClass = preload("res://scripts/GameManager.gd")
var game_manager_node: Node

var current_mode: int
var telemetry: TelemetryTracker
var time_in_current_state: float = 0.0
var time_since_last_action: float = 0.0

var stuck_threshold: float = 3.0
var is_stuck: bool = false
var last_position: Vector3 = Vector3.ZERO
var current_system: String = "None"

# Tracking progress to emit all_flows_completed
var visited_picross: bool = false
var visited_painting: bool = false

func _ready():
    if not has_user_signal("all_flows_completed"):
        add_user_signal("all_flows_completed")

func set_game_manager(gm: Node):
    game_manager_node = gm
    game_manager_node.connect("mode_changed", Callable(self, "_on_game_mode_changed"))
    current_mode = game_manager_node.current_mode
    _update_system_name()

func attach_telemetry(tracker: TelemetryTracker):
    telemetry = tracker

func _on_game_mode_changed(new_mode: int):
    current_mode = new_mode
    time_in_current_state = 0.0
    time_since_last_action = 0.0
    is_stuck = false

    if current_mode == GameManagerClass.GameMode.PICROSS_3D:
        visited_picross = true
    if current_mode == GameManagerClass.GameMode.MASQUERADE_PAINTING:
        visited_painting = true

    _update_system_name()

func _update_system_name():
    match current_mode:
        GameManagerClass.GameMode.LONE_WOLF_NARRATIVE:
            current_system = "Narrative"
        GameManagerClass.GameMode.MASQUERADE_PAINTING:
            current_system = "Painting2D"
        GameManagerClass.GameMode.PICROSS_3D:
            current_system = "Voxel3D"
        _:
            current_system = "Unknown"

func _process(delta: float):
    time_in_current_state += delta
    time_since_last_action += delta

    simulate_gameplay(delta)
    check_stuck_state()

    # Check if we have completed a full loop
    if current_mode == GameManagerClass.GameMode.LONE_WOLF_NARRATIVE and visited_picross and visited_painting:
        # Avoid firing multiple times
        visited_picross = false
        visited_painting = false
        emit_signal("all_flows_completed")

func simulate_gameplay(delta: float):
    # Simulate a player trying to solve the puzzle/level based on current mode
    match current_mode:
        GameManagerClass.GameMode.LONE_WOLF_NARRATIVE:
            if time_since_last_action > 2.0:
                perform_action("narrative_reading", {})
                # Try to press UI buttons
                if not visited_picross:
                    _find_and_press_button("Investigate 3D Voxel Sigil (Enter Picross3D)")
                else:
                    _find_and_press_button("[Perception] Inspect Canvas Patterns (Enter Masquerade Painting)")

        GameManagerClass.GameMode.MASQUERADE_PAINTING:
            if time_since_last_action > 1.0:
                # Simulate drawing lines
                var start = Vector2(randf_range(0, 800), randf_range(0, 600))
                var end = Vector2(randf_range(0, 800), randf_range(0, 600))
                perform_action("draw_line", {"start": start, "end": end})
                log_position(Vector3(end.x, end.y, 0))

                # After some drawing, click the back button
                if time_in_current_state > 3.0:
                    _find_and_press_button("Back to Narrative")

        GameManagerClass.GameMode.PICROSS_3D:
            if time_since_last_action > 0.5:
                # Simulate chiseling voxels
                var target_x = randi() % 5
                var target_y = randi() % 5
                var target_z = randi() % 5

                if randf() > 0.9:
                    pass
                else:
                    perform_action("chisel_voxel", {"x": target_x, "y": target_y, "z": target_z})
                    log_position(Vector3(target_x, target_y, target_z))

                # After some time, solve the puzzle
                if time_in_current_state > 3.0:
                    _find_and_press_button("Solve Puzzle")

func _find_and_press_button(button_text: String) -> bool:
    var root = get_tree().get_root()
    var button = _search_for_button_with_text(root, button_text)
    if button != null:
        print("[BotAgent] Pressing button: ", button_text)
        button.emit_signal("pressed")
        perform_action("press_button", {"button": button_text})
        return true
    return false

func _search_for_button_with_text(node: Node, text: String) -> Button:
    if node is Button and node.text == text:
        return node

    for child in node.get_children():
        var result = _search_for_button_with_text(child, text)
        if result != null:
            return result

    return null

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
