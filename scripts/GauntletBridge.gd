extends Node

var server := TCPServer.new()
var clients := []

func _ready():
    var err = server.listen(8090)
    if err == OK:
        print("[GauntletBridge] Listening on 8090")
    else:
        print("[GauntletBridge] Failed to listen on 8090: ", err)
        set_process(false)

func _process(delta):
    if server.is_connection_available():
        var conn = server.take_connection()
        print("[GauntletBridge] Client connected")
        clients.append(conn)

    for conn in clients:
        if conn.get_status() == StreamPeerTCP.STATUS_CONNECTED:
            var bytes = conn.get_available_bytes()
            if bytes > 0:
                var data = conn.get_string(bytes)
                _handle_command(conn, data)
        elif conn.get_status() == StreamPeerTCP.STATUS_ERROR or conn.get_status() == StreamPeerTCP.STATUS_NONE:
            clients.erase(conn)

func _handle_command(conn: StreamPeerTCP, data: String):
    var lines = data.strip_edges().split("\n")
    for line in lines:
        if line.is_empty():
            continue
        var json = JSON.new()
        var err = json.parse(line)
        if err == OK:
            var cmd = json.get_data()
            if typeof(cmd) == TYPE_DICTIONARY:
                if cmd.has("cmd"):
                    match cmd.cmd:
                        "capture":
                            if cmd.has("name"):
                                var img = get_tree().root.get_viewport().get_texture().get_image()
                                img.save_png(cmd.name)
                                _send_response(conn, {"status": "ok", "file": cmd.name})
                        "change_scene":
                            if cmd.has("target"):
                                get_tree().change_scene_to_file(cmd.target)
                                _send_response(conn, {"status": "ok"})
                        "switch_mode":
                            if cmd.has("target"):
                                var main_loop = Engine.get_main_loop()
                                if main_loop and main_loop.root:
                                    var gm = main_loop.root.get_node_or_null("GameManager")
                                    if gm:
                                        gm.switch_mode(int(cmd.target))
                                        _send_response(conn, {"status": "ok"})
                        "click_ui_button":
                            if cmd.has("target"):
                                var main_loop = Engine.get_main_loop()
                                if main_loop and main_loop.root:
                                    var btn = main_loop.root.find_child(cmd.target, true, false)
                                    if btn and btn is Button:
                                        btn.emit_signal("pressed")
                                        _send_response(conn, {"status": "ok"})
                                    else:
                                        _send_response(conn, {"status": "error", "reason": "Button not found"})
                        "load_tutorial_puzzle":
                            var main_loop = Engine.get_main_loop()
                            if main_loop and main_loop.root:
                                var gm = main_loop.root.get_node_or_null("GameManager")
                                if gm:
                                    var file_path = "res://data/puzzles/tutorial_star.json"
                                    if FileAccess.file_exists(file_path):
                                        var file = FileAccess.open(file_path, FileAccess.READ)
                                        var puzzle_dict = JSON.parse_string(file.get_as_text())
                                        gm.mode_payload = {"custom_puzzle": puzzle_dict}
                                        gm.switch_mode(gm.GameMode.ESCAPE_GAUNTLET)
                                        _send_response(conn, {"status": "ok"})
                        "solve_puzzle":
                            var main_loop = Engine.get_main_loop()
                            if main_loop and main_loop.root:
                                var grid_mgr = _find_grid_manager(main_loop.root)
                                if grid_mgr and grid_mgr.has_method("_check_win_condition"):
                                    if "has_custom_puzzle" in grid_mgr:
                                        grid_mgr.has_custom_puzzle = false
                                    if grid_mgr.has_method("_reveal_model"):
                                        grid_mgr.boss_hp = 0
                                        grid_mgr._reveal_model()
                                        _send_response(conn, {"status": "ok"})
                                    else:
                                        _send_response(conn, {"status": "error", "reason": "no _reveal_model"})
                                else:
                                    _send_response(conn, {"status": "error", "reason": "no grid_mgr"})
                        "trigger_chisel_at":
                            if cmd.has("x") and cmd.has("y") and cmd.has("z"):
                                var main_loop = Engine.get_main_loop()
                                if main_loop and main_loop.root:
                                    var grid_mgr = _find_grid_manager(main_loop.root)
                                    if grid_mgr and grid_mgr.has_method("on_chisel_requested"):
                                        grid_mgr.on_chisel_requested(Vector3i(cmd.x, cmd.y, cmd.z))
                                        _send_response(conn, {"status": "ok"})
                                    else:
                                        _send_response(conn, {"status": "error", "reason": "no grid_mgr or method"})
                                else:
                                    _send_response(conn, {"status": "error", "reason": "no main_loop"})
                        "trigger_mark_at":
                            if cmd.has("x") and cmd.has("y") and cmd.has("z"):
                                var main_loop = Engine.get_main_loop()
                                if main_loop and main_loop.root:
                                    var grid_mgr = _find_grid_manager(main_loop.root)
                                    if grid_mgr and grid_mgr.has_method("on_mark_requested"):
                                        grid_mgr.on_mark_requested(Vector3i(cmd.x, cmd.y, cmd.z))
                                        _send_response(conn, {"status": "ok"})
                                    else:
                                        _send_response(conn, {"status": "error", "reason": "no grid_mgr or method"})
                                else:
                                    _send_response(conn, {"status": "error", "reason": "no main_loop"})

func _send_response(conn: StreamPeerTCP, dict: Dictionary):
    if conn and conn.get_status() == StreamPeerTCP.STATUS_CONNECTED:
        var msg = JSON.stringify(dict) + "\n"
        conn.put_string(msg)

func _find_grid_manager(node: Node) -> Node:
    if node.name == "GridManager" or node.name == "VoxelLogic" or node.has_method("_check_win_condition") or (node.get_script() != null and node.get_script().resource_path.ends_with("GridManager.gd")):
        return node
    for child in node.get_children():
        var found = _find_grid_manager(child)
        if found:
            return found
    return null
