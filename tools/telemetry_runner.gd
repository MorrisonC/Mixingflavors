extends SceneTree

var telemetry_tracker: TelemetryTracker
var bot_agent: BotAgent
var game_manager_node: Node
var main_scene_node: Node

const TelemetryTrackerClass = preload("res://scripts/telemetry_tracker.gd")
const BotAgentClass = preload("res://tools/bot_agent.gd")

var total_test_duration: float = 30.0 # Total fallback timeout
var time_elapsed: float = 0.0

const GameManagerClass = preload("res://scripts/GameManager.gd")

func _init():
    print("[TelemetryRunner] Initializing headless test run...")

    var root = get_root()

    # In Godot 4 headless script runners, Autoloads are NOT instantiated globally if you just run a script.
    # We must instantiate it and add it as a child of root, named "GameManager"
    game_manager_node = GameManagerClass.new()
    game_manager_node.name = "GameManager"
    root.add_child(game_manager_node)

    # Initialize Main Scene which handles UI routing
    var main_scene = load("res://scenes/Main.tscn")
    main_scene_node = main_scene.instantiate()
    root.add_child(main_scene_node)

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
    bot_agent.set_game_manager(game_manager_node)

    if bot_agent.has_user_signal("all_flows_completed") == false:
        bot_agent.add_user_signal("all_flows_completed")
    bot_agent.connect("all_flows_completed", Callable(self, "finish_testing"))

    print("[TelemetryRunner] Setup complete. Bot starting natural flow.")

    # Start tracking for the initial mode
    var mode_name = GameManagerClass.GameMode.keys()[game_manager_node.current_mode]
    telemetry_tracker.start_level(mode_name)

    # Listen for mode changes to track telemetry accurately
    game_manager_node.connect("mode_changed", Callable(self, "_on_mode_changed"))


func _on_mode_changed(new_mode):
    telemetry_tracker.end_level()
    var mode_name = GameManagerClass.GameMode.keys()[new_mode]
    telemetry_tracker.start_level(mode_name)
    print("[TelemetryRunner] Tracked mode change to: ", mode_name)


func _process(delta: float):
    time_elapsed += delta

    if time_elapsed >= total_test_duration:
        print("[TelemetryRunner] Test timeout reached.")
        finish_testing()

func finish_testing():
    print("[TelemetryRunner] Testing finished. Saving telemetry...")
    telemetry_tracker.end_level()
    telemetry_tracker.save_telemetry()
    quit(0)
