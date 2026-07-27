extends SceneTree

var telemetry_tracker: TelemetryTracker
var bot_agent: BotAgent
var game_manager_node: GameManager

var test_duration: float = 20.0
var time_elapsed: float = 0.0

var modes_to_test = [
    GameManager.GameMode.LONE_WOLF_NARRATIVE,
    GameManager.GameMode.MASQUERADE_PAINTING,
    GameManager.GameMode.PICROSS_3D,
    GameManager.GameMode.ESCAPE_GAUNTLET
]
var current_mode_index: int = 0

func _init():
    print("[TelemetryRunner] Initializing headless test run...")

    # Initialize the main scene or core nodes
    var root = get_root()

    # Check if GameManager exists, if not create it
    game_manager_node = GameManager.new()
    game_manager_node.name = "GameManager"
    root.add_child(game_manager_node)

    # Setup Telemetry Tracker
    telemetry_tracker = TelemetryTracker.new()
    telemetry_tracker.name = "TelemetryTracker"
    root.add_child(telemetry_tracker)

    # Setup Bot Agent
    bot_agent = BotAgent.new()
    bot_agent.name = "BotAgent"
    root.add_child(bot_agent)

    # Connect them
    bot_agent.attach_telemetry(telemetry_tracker)

    print("[TelemetryRunner] Setup complete. Starting first test phase.")
    start_next_mode_test()

func start_next_mode_test():
    if current_mode_index >= modes_to_test.size():
        finish_testing()
        return

    var mode = modes_to_test[current_mode_index]
    var mode_name = GameManager.GameMode.keys()[mode]

    print("[TelemetryRunner] Starting test for mode: ", mode_name)
    game_manager_node.switch_mode(mode)
    telemetry_tracker.start_level(mode_name)

    time_elapsed = 0.0
    current_mode_index += 1

func _process(delta: float):
    time_elapsed += delta

    if time_elapsed >= test_duration / modes_to_test.size():
        telemetry_tracker.end_level()
        print("[TelemetryRunner] Finished testing current mode.")
        start_next_mode_test()

func finish_testing():
    print("[TelemetryRunner] All tests completed. Saving telemetry...")
    telemetry_tracker.save_telemetry()
    quit(0)
