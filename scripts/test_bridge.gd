extends Node

var game_api_callback = null

func _ready() -> void:
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

    if action == "get_current_mode":
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
                    gm.switch_mode(target)
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
                # Simulate winning by marking all blocks correctly or forcing state
                # As this is a test bridge, let's look for ways to force solve
                if "has_custom_puzzle" in grid_mgr:
                    grid_mgr.has_custom_puzzle = false # Make it easy

                # Directly reveal the model to trigger the puzzle solved event
                if grid_mgr.has_method("_reveal_model"):
                    grid_mgr.boss_hp = 0
                    grid_mgr._reveal_model()
                    result = true
                    print("[TestBridge] Triggering win condition via _reveal_model")
                else:
                    result = false
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

    if result != null:
        var window = JavaScriptBridge.get_interface("window")
        if window:
            var js_code = ""
            if typeof(result) == TYPE_STRING:
                js_code = "window.__godot_resolve('" + str(result) + "');"
            elif typeof(result) == TYPE_INT or typeof(result) == TYPE_FLOAT:
                js_code = "window.__godot_resolve(" + str(result) + ");"
            elif typeof(result) == TYPE_BOOL:
                js_code = "window.__godot_resolve(" + ("true" if result else "false") + ");"

            JavaScriptBridge.eval(js_code, true)
            print("[TestBridge] Resolved via eval: ", js_code)
    else:
        var window = JavaScriptBridge.get_interface("window")
        if window:
            JavaScriptBridge.eval("window.__godot_resolve(null);", true)
            print("[TestBridge] Resolved via eval: null")

func _find_grid_manager(node: Node) -> Node:
    if node.name == "GridManager" or node.name == "VoxelLogic" or node.has_method("_check_win_condition") or node.get_script() != null and node.get_script().resource_path.ends_with("GridManager.gd"):
        return node
    for child in node.get_children():
        var found = _find_grid_manager(child)
        if found:
            return found
    return null
