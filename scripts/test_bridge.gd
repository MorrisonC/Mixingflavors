extends Node

var game_api_callback = null
var _bridge_enabled: bool = false

func _ready() -> void:
    _bridge_enabled = OS.is_debug_build() or OS.has_feature("e2e")
    if not _bridge_enabled:
        return
    if ClassDB.class_exists("JavaScriptBridge"):
        game_api_callback = JavaScriptBridge.create_callback(_on_js_call)
        var window = JavaScriptBridge.get_interface("window")
        if window:
            window.gameAPI = game_api_callback
            print("[TestBridge] gameAPI injected into window")
        else:
            print("[TestBridge] window interface not found")
    else:
        print("[TestBridge] JavaScriptBridge class not found")

func _on_js_call(args):
    if not _bridge_enabled:
        return
    print("[TestBridge] _on_js_call called with args: ", args)
    if args.size() == 0:
        return

    var js_obj = args[0]
    var action = ""
    if typeof(js_obj) == TYPE_STRING:
        action = js_obj
    else:
        if js_obj.length > 0:
            action = js_obj[0]

    print("[TestBridge] _on_js_call action: ", action)
    var result = null

    if action == "pause_engine":
        get_tree().paused = true
        result = true

    elif action == "unpause_engine":
        get_tree().paused = false
        result = true

    elif action == "get_current_mode":
        var main_loop = Engine.get_main_loop()
        if main_loop and main_loop.root:
            var gm = main_loop.root.get_node_or_null("GameManager")
            if gm:
                result = int(gm.current_mode)
            else:
                result = -1
        else:
            result = -1

    elif action == "switch_mode":
        if typeof(js_obj) != TYPE_STRING and js_obj.length > 1:
            var main_loop = Engine.get_main_loop()
            if main_loop and main_loop.root:
                var gm = main_loop.root.get_node_or_null("GameManager")
                if gm:
                    var target = int(js_obj[1])
                    var payload: Dictionary = {}
                    if js_obj.length > 2 and js_obj[2] is Dictionary:
                        payload = js_obj[2]
                    gm.switch_mode(target, payload)
                    result = true

    elif action == "select_difficulty":
        if typeof(js_obj) != TYPE_STRING and js_obj.length > 1:
            var main_loop = Engine.get_main_loop()
            if main_loop and main_loop.root:
                var gm = main_loop.root.get_node_or_null("GameManager")
                if gm:
                    var difficulty: String = str(js_obj[1]).to_lower()
                    if difficulty in ["easy", "medium", "hard", "endless"]:
                        gm.set("selected_difficulty_mode", difficulty)
                        gm.switch_mode(gm.GameMode.ESCAPE_GAUNTLET, {"difficulty": difficulty, "run_seed": 0})
                        result = true

    elif action == "get_selected_difficulty":
        var main_loop = Engine.get_main_loop()
        if main_loop and main_loop.root:
            var gm = main_loop.root.get_node_or_null("GameManager")
            if gm:
                result = str(gm.get("selected_difficulty_mode"))

    elif action == "get_active_puzzle_id":
        var main_loop = Engine.get_main_loop()
        if main_loop and main_loop.root:
            var grid_mgr = _find_grid_manager(main_loop.root)
            if grid_mgr:
                var puzzle_data: Variant = grid_mgr.get("custom_puzzle_data")
                if puzzle_data is Dictionary:
                    result = str((puzzle_data as Dictionary).get("id", ""))

    elif action == "get_completion":
        var main_loop = Engine.get_main_loop()
        if main_loop and main_loop.root:
            var save_manager = main_loop.root.get_node_or_null("SaveManager")
            if save_manager and save_manager.has_method("get_completion"):
                result = save_manager.call("get_completion")

    elif action == "get_player_stats":
        var main_loop = Engine.get_main_loop()
        if main_loop and main_loop.root:
            var save_manager = main_loop.root.get_node_or_null("SaveManager")
            if save_manager and save_manager.has_method("get_player_stats"):
                result = save_manager.call("get_player_stats")

    elif action == "get_gauntlet_state":
        var main_loop = Engine.get_main_loop()
        if main_loop and main_loop.root:
            var gauntlet = main_loop.root.get_node_or_null("Main/SubViewportContainer/SubViewport/EscapeGauntlet")
            if gauntlet:
                result = {
                    "time_left": float(gauntlet.get("time_left")),
                    "current_round": int(gauntlet.get("current_round")),
                    "is_game_over": bool(gauntlet.get("is_game_over")),
                }

    elif action == "get_victory_state":
        var main_loop = Engine.get_main_loop()
        if main_loop and main_loop.root:
            var victory = _find_named_node(main_loop.root, "VictoryScreen")
            result = {
                "found": victory != null,
                "visible": victory is Control and victory.is_visible_in_tree(),
                "snapshot": victory.call("get_result_snapshot") if victory != null and victory.has_method("get_result_snapshot") else {},
            }

    elif action == "load_tutorial_puzzle":
        var main_loop = Engine.get_main_loop()
        if main_loop and main_loop.root:
            var gm = main_loop.root.get_node_or_null("GameManager")
            if gm:
                var file_path = "res://data/puzzles/tutorial_star.json"
                if FileAccess.file_exists(file_path):
                    var file = FileAccess.open(file_path, FileAccess.READ)
                    var puzzle_dict = JSON.parse_string(file.get_as_text())
                    gm.switch_mode(gm.GameMode.VOXEL_LOGIC, {"custom_puzzle": puzzle_dict})
                    result = true

    elif action == "get_puzzle_state":
        var main_loop = Engine.get_main_loop()
        if main_loop and main_loop.root:
            var grid_mgr = _find_grid_manager(main_loop.root)
            if grid_mgr:
                result = "SOLVED" if (grid_mgr.has_method("is_solved") and grid_mgr.is_solved()) else "IN_PROGRESS"
            else:
                result = "ERROR_GRID_MGR_NOT_FOUND"
        else:
            result = "ERROR_MAIN_LOOP"

    elif action == "solve_puzzle":
        var main_loop = Engine.get_main_loop()
        if main_loop and main_loop.root:
            var grid_mgr = _find_grid_manager(main_loop.root)
            if grid_mgr and grid_mgr.has_method("_check_win_condition"):
                # Drive the same canonical state transitions as a player. This
                # keeps the E2E check on the real win/reveal path instead of
                # calling the private reveal animation directly.
                var target_solution: Dictionary = grid_mgr.get("target_solution")
                for coordinate: Vector3i in target_solution.keys():
                    if not bool(target_solution[coordinate]) and grid_mgr.has_method("hammer_cell"):
                        grid_mgr.call("hammer_cell", coordinate)
                grid_mgr.call("_check_win_condition")
                result = not bool(grid_mgr.get("is_puzzle_active"))
                print("[TestBridge] Completed puzzle through canonical cell actions")
            else:
                result = false

    elif action == "get_button_state":
        if typeof(js_obj) != TYPE_STRING and js_obj.length > 1:
            var btn_path = js_obj[1]
            var btn = get_tree().root.get_node_or_null(btn_path)
            if btn and btn is Button:
                result = not btn.disabled

    elif action == "press_button":
        if typeof(js_obj) != TYPE_STRING and js_obj.length > 1:
            var btn_path = js_obj[1]
            var btn = get_tree().root.get_node_or_null(btn_path)
            if btn and btn is Button:
                btn.emit_signal("pressed")
                result = true
            else:
                result = false

    elif action == "get_node_property":
        if typeof(js_obj) != TYPE_STRING and js_obj.length > 2:
            var node_path = js_obj[1]
            var prop_name = js_obj[2]
            var node = get_tree().root.get_node_or_null(node_path)
            if node:
                result = node.get(prop_name)

    elif action == "trigger_mark_at":
        if typeof(js_obj) != TYPE_STRING and js_obj.length > 3:
            var main_loop = Engine.get_main_loop()
            if main_loop and main_loop.root:
                var grid_mgr = _find_grid_manager(main_loop.root)
                if grid_mgr and grid_mgr.has_method("on_mark_requested"):
                    grid_mgr.on_mark_requested(Vector3i(js_obj[1], js_obj[2], js_obj[3]))
                    result = true


    elif action == "trigger_chisel_at":
        if typeof(js_obj) != TYPE_STRING and js_obj.length > 3:
            var main_loop = Engine.get_main_loop()
            if main_loop and main_loop.root:
                var grid_mgr = _find_grid_manager(main_loop.root)
                if grid_mgr and grid_mgr.has_method("on_chisel_requested"):
                    grid_mgr.on_chisel_requested(Vector3i(js_obj[1], js_obj[2], js_obj[3]))
                    result = true

    elif action == "is_cell_chiseled":
        if typeof(js_obj) != TYPE_STRING and js_obj.length > 3:
            var main_loop = Engine.get_main_loop()
            if main_loop and main_loop.root:
                var grid_mgr = _find_grid_manager(main_loop.root)
                if grid_mgr and grid_mgr.has_method("is_cell_chiseled"):
                    result = grid_mgr.is_cell_chiseled(Vector3i(js_obj[1], js_obj[2], js_obj[3]))

    elif action == "get_cell_state":
        # Reports a cell's canonical state so a real touch tap can be verified
        # end to end instead of only checking that the screen looks alive.
        if typeof(js_obj) != TYPE_STRING and js_obj.length > 3:
            var main_loop = Engine.get_main_loop()
            if main_loop and main_loop.root:
                var grid_mgr = _find_grid_manager(main_loop.root)
                if grid_mgr:
                    var cell := Vector3i(js_obj[1], js_obj[2], js_obj[3])
                    if grid_mgr.has_method("is_cell_chiseled") and grid_mgr.is_cell_chiseled(cell):
                        result = "destroyed"
                    elif grid_mgr.has_method("is_cell_marked") and grid_mgr.is_cell_marked(cell):
                        result = "marked"
                    else:
                        result = "unbroken"

    elif action == "get_cell_at_normalized_pos":
        # Runs the game's OWN hit test at a normalized viewport position, so a
        # test can confirm that a screen point really resolves to a voxel
        # instead of trusting its own projection math.
        if typeof(js_obj) != TYPE_STRING and js_obj.length > 2:
            var main_loop = Engine.get_main_loop()
            if main_loop and main_loop.root:
                var grid_mgr = _find_grid_manager(main_loop.root)
                var controls := _find_touch_controls(main_loop.root)
                if grid_mgr and controls and controls.has_method("_raycast_block"):
                    var viewport_size := Vector2(controls.get_viewport().get_visible_rect().size)
                    if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
                        result = {"ok": false, "reason": "no_viewport"}
                    else:
                        var point := Vector2(float(js_obj[1]) * viewport_size.x, float(js_obj[2]) * viewport_size.y)
                        var cell: Vector3i = controls.call("_raycast_block", point)
                        result = {
                            "ok": true,
                            "x": cell.x,
                            "y": cell.y,
                            "z": cell.z,
                            "valid": cell.x >= 0,
                        }

    elif action == "is_target_cell":
        if typeof(js_obj) != TYPE_STRING and js_obj.length > 3:
            var main_loop = Engine.get_main_loop()
            if main_loop and main_loop.root:
                var grid_mgr = _find_grid_manager(main_loop.root)
                if grid_mgr and grid_mgr.has_method("is_target_cell"):
                    result = grid_mgr.is_target_cell(Vector3i(js_obj[1], js_obj[2], js_obj[3]))

    elif action == "get_cell_screen_pos":
        # Projects a cell to normalized viewport coordinates so a browser test can
        # dispatch a genuine tap at that voxel. Normalized output keeps the test
        # independent of the canvas stretch mode and device pixel ratio.
        if typeof(js_obj) != TYPE_STRING and js_obj.length > 3:
            var main_loop = Engine.get_main_loop()
            if main_loop and main_loop.root:
                var grid_mgr = _find_grid_manager(main_loop.root)
                var camera := _find_active_camera(main_loop.root)
                if grid_mgr and camera:
                    var cell := Vector3i(js_obj[1], js_obj[2], js_obj[3])
                    var blocks: Dictionary = grid_mgr.get("blocks")
                    var world_position := Vector3.ZERO
                    if blocks is Dictionary and blocks.has(cell) and blocks[cell] is Node3D:
                        world_position = (blocks[cell] as Node3D).global_position
                    else:
                        world_position = grid_mgr.global_transform * _cell_center_offset(grid_mgr, cell)
                    var viewport_size := Vector2(camera.get_viewport().get_visible_rect().size)
                    if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
                        result = {"ok": false, "reason": "no_viewport"}
                    else:
                        var screen := camera.unproject_position(world_position)
                        result = {
                            "ok": true,
                            "x": screen.x / viewport_size.x,
                            "y": screen.y / viewport_size.y,
                            "behind": camera.is_position_behind(world_position),
                        }

    elif action == "get_camera_state":
        var main_loop = Engine.get_main_loop()
        if main_loop and main_loop.root:
            var camera := _find_active_camera(main_loop.root)
            var pivot: Node = camera.get_parent() if camera else null
            while pivot != null and not pivot.has_method("fit_to_grid"):
                pivot = pivot.get_parent()
            if pivot and pivot.has_method("fit_to_grid"):
                result = {
                    "target_distance": float(pivot.get("target_distance")),
                    "current_distance": float(pivot.get("current_distance")),
                    "min_distance": float(pivot.get("min_distance")),
                    "fitted_distance": float(pivot.get("_last_fitted_distance")),
                    "spring_length": float(pivot.get("spring_arm").spring_length) if pivot.get("spring_arm") else -1.0,
                }

    elif action == "get_ui_rects":
        # Control-space rects for the puzzle's own controls. Same coordinate
        # space for every entry, so a test can prove non-overlap and that each
        # control is fully inside the visible rect.
        var main_loop = Engine.get_main_loop()
        if main_loop and main_loop.root:
            var grid_mgr = _find_grid_manager(main_loop.root)
            if grid_mgr:
                var names := ["ChiselButton", "MarkButton", "SliceToggleButton", "UndoButton", "HintButton", "ResetViewButton", "LeaveButton"]
                var rects: Array = []
                for button_name: String in names:
                    var button := _find_named_node(grid_mgr, button_name)
                    if button is Control:
                        rects.append(_control_rect(button, button_name))
                # The guided tutorial banner is a separate CanvasLayer, so a test
                # that only sampled the puzzle toolbar could not prove the
                # instruction is actually visible rather than hidden behind the
                # HUD. Report only the visible panel: the MarginContainer that
                # positions it is a full-screen, transparent layout node and
                # would trivially "overlap" every real control.
                var tutorial_ui := _find_named_node(grid_mgr, "TutorialUI")
                if tutorial_ui:
                    var tutorial_banner: Node = tutorial_ui.get_node_or_null("MarginContainer/VBoxContainer/BannerPanel")
                    if tutorial_banner is Control:
                        rects.append(_control_rect(tutorial_banner, "TutorialBannerPanel"))
                var visible_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(get_viewport().get_visible_rect().size))
                result = {"rects": rects, "visible": {"x": visible_rect.position.x, "y": visible_rect.position.y, "w": visible_rect.size.x, "h": visible_rect.size.y}}

    elif action == "set_edit_mode":
        if typeof(js_obj) != TYPE_STRING and js_obj.length > 1:
            var mode_name = js_obj[1]
            var main_loop = Engine.get_main_loop()
            if main_loop and main_loop.root:
                var grid_mgr = _find_grid_manager(main_loop.root)
                if grid_mgr:
                    if mode_name == "chisel" and grid_mgr.has_method("_on_chisel_mode_selected"):
                        grid_mgr._on_chisel_mode_selected()
                        result = true
                    elif mode_name == "paint" and grid_mgr.has_method("_on_paint_mode_selected"):
                        grid_mgr._on_paint_mode_selected()
                        result = true
                    elif mode_name == "mark" and grid_mgr.has_method("_on_mark_mode_selected"):
                        grid_mgr._on_mark_mode_selected()
                        result = true

    elif action == "set_slice":
        if typeof(js_obj) != TYPE_STRING and js_obj.length > 2:
            var axis = js_obj[1]
            var val = js_obj[2]
            var main_loop = Engine.get_main_loop()
            if main_loop and main_loop.root:
                var grid_mgr = _find_grid_manager(main_loop.root)
                if grid_mgr:
                    if axis == "x" and grid_mgr.has_method("_on_slice_x_changed"):
                        grid_mgr._on_slice_x_changed(val)
                        result = true
                    elif axis == "y" and grid_mgr.has_method("_on_slice_y_changed"):
                        grid_mgr._on_slice_y_changed(val)
                        result = true
                    elif axis == "z" and grid_mgr.has_method("_on_slice_z_changed"):
                        grid_mgr._on_slice_z_changed(val)
                        result = true

    elif action == "toggle_slice":
        var main_loop = Engine.get_main_loop()
        if main_loop and main_loop.root:
            var grid_mgr = _find_grid_manager(main_loop.root)
            if grid_mgr and grid_mgr.has_method("_on_slice_toggle_pressed"):
                grid_mgr._on_slice_toggle_pressed()
                result = true

    elif action == "click_ui_button":
        if typeof(js_obj) != TYPE_STRING and js_obj.length > 1:
            var btn_name = js_obj[1]
            var main_loop = Engine.get_main_loop()
            if main_loop and main_loop.root:
                var btn = null

                if btn_name == "menu_play":
                    btn = main_loop.root.get_node_or_null("/root/Main/CanvasLayer/UIContainer/MainMenu/VBoxContainer/PlayButton")
                elif btn_name == "leave":
                    btn = main_loop.root.get_node_or_null("/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/CanvasLayer/UI/QuitButton")
                elif btn_name == "confirm_yes":
                    btn = main_loop.root.get_node_or_null("/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/CanvasLayer/UI/ConfirmDialog/VBoxContainer/HBoxContainer/YesButton")
                elif btn_name == "confirm_no":
                    btn = main_loop.root.get_node_or_null("/root/Main/SubViewportContainer/SubViewport/EscapeGauntlet/CanvasLayer/UI/ConfirmDialog/VBoxContainer/HBoxContainer/NoButton")

                if btn and btn is Button:
                    btn.emit_signal("pressed")
                    result = true
                else:
                    result = false

    if ClassDB.class_exists("JavaScriptBridge"):
        var window = JavaScriptBridge.get_interface("window")
        if window:
            var serialized_result: String = JSON.stringify(result)
            var js_code := "window.__godot_resolve(" + serialized_result + ");"
            JavaScriptBridge.eval(js_code, true)
            print("[TestBridge] Resolved callback with a JSON-encoded result")

func _control_rect(control: Control, entry_name: String) -> Dictionary:
    return {
        "name": entry_name,
        "path": String(control.get_path()),
        "x": control.global_position.x,
        "y": control.global_position.y,
        "w": control.size.x,
        "h": control.size.y,
        "visible": control.is_visible_in_tree(),
        "disabled": (control is Button) and (control as Button).disabled,
    }


func _find_named_node(node: Node, target_name: String) -> Node:
    if node.name == target_name:
        return node
    for child in node.get_children():
        var found := _find_named_node(child, target_name)
        if found:
            return found
    return null


func _find_grid_manager(node: Node) -> Node:
    if node.name == "GridManager" or node.name == "VoxelLogic" or node.has_method("_check_win_condition") or node.get_script() != null and node.get_script().resource_path.ends_with("GridManager.gd"):
        return node
    for child in node.get_children():
        var found = _find_grid_manager(child)
        if found:
            return found
    return null


func _find_active_camera(node: Node) -> Camera3D:
    if node is Camera3D and (node as Camera3D).current:
        return node as Camera3D
    for child in node.get_children():
        var found = _find_active_camera(child)
        if found:
            return found
    return null


func _cell_center_offset(grid_mgr: Node, cell: Vector3i) -> Vector3:
    var grid_size: Vector3i = grid_mgr.get("grid_size")
    return Vector3(cell) - Vector3(grid_size) / 2.0 + Vector3(0.5, 0.5, 0.5)


func _find_touch_controls(node: Node) -> Node:
    if node.get_script() != null and node.get_script().resource_path.ends_with("MobileTouchControls.gd"):
        return node
    for child in node.get_children():
        var found = _find_touch_controls(child)
        if found:
            return found
    return null
