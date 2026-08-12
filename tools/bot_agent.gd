class_name BotAgent
extends Node

const GameManagerClass = preload("res://scripts/GameManager.gd")
const GridManagerClass = preload("res://scripts/GridManager.gd")
const VoxelLogicSolverClass = preload("res://scripts/VoxelLogicSolver.gd")

var game_manager_node: Node
var grid_manager_node: Node

var current_mode: int
var telemetry: Node
var time_in_current_state: float = 0.0
var time_since_last_action: float = 0.0

var stuck_threshold: float = 3.0
var is_stuck: bool = false
var last_position: Vector3 = Vector3.ZERO
var current_system: String = "None"

var visited_picross: bool = false
var visited_escape: bool = false
var last_known_grid_state = {}

func _ready():
    if not has_user_signal("all_flows_completed"):
        add_user_signal("all_flows_completed")

func set_game_manager(gm: Node):
    game_manager_node = gm
    game_manager_node.connect("mode_changed", Callable(self, "_on_game_mode_changed"))
    current_mode = game_manager_node.current_mode
    _update_system_name()

func attach_telemetry(tracker: Node):
    telemetry = tracker

func _on_game_mode_changed(new_mode: int):
    current_mode = new_mode
    time_in_current_state = 0.0
    time_since_last_action = 0.0
    is_stuck = false

    if current_mode == GameManagerClass.GameMode.VOXEL_LOGIC:
        visited_picross = true
    if current_mode == GameManagerClass.GameMode.ESCAPE_GAUNTLET:
        visited_escape = true

    _update_system_name()

func _update_system_name():
    match current_mode:
        GameManagerClass.GameMode.MAIN_MENU:
            current_system = "MainMenu"
        GameManagerClass.GameMode.VOXEL_LOGIC:
            current_system = "Voxel3D"
        GameManagerClass.GameMode.ESCAPE_GAUNTLET:
            current_system = "EscapeGauntlet"
        GameManagerClass.GameMode.MASQUERADE_PAINTING:
            current_system = "Painting2D"
        _:
            current_system = "Unknown"

func _process(delta: float):
    time_in_current_state += delta
    time_since_last_action += delta

    simulate_gameplay(delta)
    check_stuck_state()

    if current_mode == GameManagerClass.GameMode.MAIN_MENU and visited_picross and visited_escape:
        visited_picross = false
        visited_escape = false
        emit_signal("all_flows_completed")

func simulate_gameplay(delta: float):
    match current_mode:
        GameManagerClass.GameMode.MAIN_MENU:
            if time_since_last_action > 2.0:
                print("[BotAgent] In Main Menu. visited_picross=", visited_picross, " visited_escape=", visited_escape)
                if not visited_picross:
                    var pressed = _find_and_press_button("Level Select")
                    if not pressed:
                        pressed = _find_and_press_button("Play")
                elif not visited_escape:
                    var pressed = _find_and_press_button("Play")
                    if not pressed:
                        pressed = _find_and_press_button("Easy")

        GameManagerClass.GameMode.PUZZLE_SELECTION:
            if time_since_last_action > 2.0:
                print("[BotAgent] In Puzzle Selection, looking for a puzzle button...")
                var buttons = _get_all_buttons(get_tree().get_root())
                var puzzle_btn = null
                for b in buttons:
                    if ("Level" in b.text or "Puzzle" in b.text or "#" in b.text or "★" in b.text) and not "Select" in b.text and b.text != "Back to Menu" and not "Easy" in b.text and not "Medium" in b.text and not "Hard" in b.text:
                        puzzle_btn = b
                        break

                if puzzle_btn == null and buttons.size() > 0:
                    for b in buttons:
                        if b.text != "Back to Menu":
                            puzzle_btn = b
                            break

                if puzzle_btn == null and buttons.size() > 0:
                    puzzle_btn = buttons[randi() % buttons.size()]

                if puzzle_btn:
                    print("[BotAgent] Pressing puzzle selection button: ", puzzle_btn.text)
                    puzzle_btn.pressed.emit()
                    perform_action("press_random_button", {"button": puzzle_btn.text})

        GameManagerClass.GameMode.VOXEL_LOGIC:
            if grid_manager_node == null:
                grid_manager_node = _find_grid_manager(get_tree().get_root())

            if grid_manager_node != null and time_since_last_action > 0.2:
                _simulate_voxel_logic()
            else:
                if grid_manager_node == null and time_since_last_action > 2.0:
                    print("[BotAgent] grid_manager_node is null in VOXEL_LOGIC!")

        GameManagerClass.GameMode.ESCAPE_GAUNTLET:
            if grid_manager_node == null:
                grid_manager_node = _find_grid_manager(get_tree().get_root())

            if grid_manager_node != null and time_since_last_action > 0.2:
                _simulate_voxel_logic()

func _simulate_voxel_logic():
    if not is_instance_valid(grid_manager_node):
        return

    if grid_manager_node.has_method("check_puzzle_complete") and grid_manager_node.check_puzzle_complete():
        if time_in_current_state > 2.0:
            print("[BotAgent] Puzzle complete! Going back to Menu...")
            var btn1 = _find_and_press_button("Next Level")
            if not btn1:
                _find_and_press_button("Back to Menu")
                _find_and_press_button("Level Select")
            get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.MAIN_MENU)
        return

    var dims = grid_manager_node.grid_size
    var current_grid_state = {}

    if not grid_manager_node.custom_puzzle_data.has("hints"):
        return

    var hints = grid_manager_node.custom_puzzle_data["hints"]

    var valid_unbroken = []

    for x in range(dims.x):
        for y in range(dims.y):
            for z in range(dims.z):
                var pos = Vector3i(x, y, z)
                if grid_manager_node.is_cell_unbroken(pos):
                    if grid_manager_node.is_cell_marked(pos):
                        current_grid_state[pos] = VoxelLogicSolverClass.CellState.PAINTED
                    else:
                        current_grid_state[pos] = VoxelLogicSolverClass.CellState.UNKNOWN
                        valid_unbroken.append(pos)
                elif grid_manager_node.is_cell_chiseled(pos):
                    current_grid_state[pos] = VoxelLogicSolverClass.CellState.BLANK
                else:
                    current_grid_state[pos] = VoxelLogicSolverClass.CellState.UNKNOWN

    if valid_unbroken.is_empty():
        return

    var solution = VoxelLogicSolverClass.solve(dims, hints)

    var moved = false
    for pos in valid_unbroken:
        if solution.has(pos):
            var should_be_painted = solution[pos]
            if should_be_painted:
                if not grid_manager_node.is_cell_marked(pos):
                    grid_manager_node.mark_cell(pos)
                    perform_action("mark_voxel", {"x": pos.x, "y": pos.y, "z": pos.z})
                    log_position(Vector3(pos.x, pos.y, pos.z))
                    print("[BotAgent] Deduced MARK: ", pos)
                    moved = true
                    break
            else:
                grid_manager_node.hammer_cell(pos)
                perform_action("chisel_voxel", {"x": pos.x, "y": pos.y, "z": pos.z})
                log_position(Vector3(pos.x, pos.y, pos.z))
                print("[BotAgent] Deduced CHISEL: ", pos)
                moved = true
                break

    if not moved and not valid_unbroken.is_empty():
        var random_pos = valid_unbroken[randi() % valid_unbroken.size()]
        grid_manager_node.hammer_cell(random_pos)
        perform_action("forced_guess", {"x": random_pos.x, "y": random_pos.y, "z": random_pos.z, "action": "chisel"})
        log_position(Vector3(random_pos.x, random_pos.y, random_pos.z))
        print("[BotAgent] Forced GUESS CHISEL: ", random_pos)

func _find_grid_manager(node: Node) -> Node:
    if node.name == "GridManager" or node is GridManagerClass:
        return node
    for child in node.get_children():
        var result = _find_grid_manager(child)
        if result != null:
            return result
    return null

func _find_and_press_button(button_text: String) -> bool:
    var root = get_tree().get_root()
    var button = _search_for_button_with_text(root, button_text)
    if button != null:
        print("[BotAgent] Pressing button: ", button_text)
        button.pressed.emit()
        perform_action("press_button", {"button": button_text})
        return true
    return false

func _search_for_button_with_text(node: Node, text: String) -> Button:
    if node is Button and text in node.text and node.is_visible_in_tree():
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

func _get_all_buttons(node: Node) -> Array:
    var result = []
    if node is Button and node.is_visible_in_tree() and node.text != "Back":
        result.append(node)
    for child in node.get_children():
        result.append_array(_get_all_buttons(child))
    return result
