extends Node

# WebSocket State Streaming & Harness Server for Headless Testing and Telemetry
var tcp_server: TCPServer = TCPServer.new()
var clients: Array = [] # Array of WebSocketPeer instances
@export var port: int = 9080

func _ready() -> void:
	var err = tcp_server.listen(port)
	if err == OK:
		print("[WebSocketServerBridge] Server listening on port %d" % port)
	else:
		print("[WebSocketServerBridge] Failed to start server on port %d, error: %d" % [port, err])

func _process(_delta: float) -> void:
	if tcp_server.is_connection_available():
		var conn = tcp_server.take_connection()
		if conn:
			var ws_peer = WebSocketPeer.new()
			var err = ws_peer.accept_stream(conn)
			if err == OK:
				clients.append(ws_peer)
				print("[WebSocketServerBridge] Client connecting...")

	var i = clients.size() - 1
	while i >= 0:
		var ws: WebSocketPeer = clients[i]
		ws.poll()
		var state = ws.get_ready_state()

		if state == WebSocketPeer.STATE_OPEN:
			while ws.get_available_packet_count() > 0:
				var packet = ws.get_packet()
				var message_str = packet.get_string_from_utf8()
				_handle_message(ws, message_str)
		elif state == WebSocketPeer.STATE_CLOSED or state == WebSocketPeer.STATE_CLOSING:
			clients.remove_at(i)
			print("[WebSocketServerBridge] Client disconnected.")

		i -= 1

func _handle_message(ws: WebSocketPeer, message_str: String) -> void:
	var json = JSON.new()
	var parse_err = json.parse(message_str)
	if parse_err != OK:
		_send_response(ws, {"status": "error", "message": "Invalid JSON"})
		return

	var req = json.get_data()
	if typeof(req) != TYPE_DICTIONARY:
		_send_response(ws, {"status": "error", "message": "Payload must be Dictionary"})
		return

	var id = req.get("id", "")
	var action = req.get("action", "")
	var data = req.get("data", {})

	var result = _execute_action(action, data)
	_send_response(ws, {"id": id, "action": action, "result": result, "status": "ok"})

func _send_response(ws: WebSocketPeer, dict: Dictionary) -> void:
	var json_str = JSON.stringify(dict)
	ws.send_text(json_str)

func _execute_action(action: String, data: Dictionary) -> Variant:
	var root = get_tree().root

	if action == "ping":
		return "pong"

	elif action == "get_current_mode":
		var gm = root.get_node_or_null("GameManager")
		return int(gm.current_mode) if gm else -1

	elif action == "switch_mode":
		var gm = root.get_node_or_null("GameManager")
		if gm and data.has("mode"):
			gm.switch_mode(int(data["mode"]))
			return true
		return false

	elif action == "get_puzzle_state":
		var grid_mgr = _find_grid_manager(root)
		if grid_mgr:
			return "SOLVED" if (grid_mgr.has_method("check_puzzle_complete") and grid_mgr.check_puzzle_complete()) else "IN_PROGRESS"
		return "GRID_NOT_FOUND"

	elif action == "chisel":
		var grid_mgr = _find_grid_manager(root)
		if grid_mgr and data.has("x") and data.has("y") and data.has("z"):
			var pos = Vector3i(int(data["x"]), int(data["y"]), int(data["z"]))
			grid_mgr.on_chisel_requested(pos)
			return true
		return false

	elif action == "mark":
		var grid_mgr = _find_grid_manager(root)
		if grid_mgr and data.has("x") and data.has("y") and data.has("z"):
			var pos = Vector3i(int(data["x"]), int(data["y"]), int(data["z"]))
			grid_mgr.on_mark_requested(pos)
			return true
		return false

	elif action == "set_slice":
		var grid_mgr = _find_grid_manager(root)
		if grid_mgr and data.has("axis") and data.has("value"):
			var axis = str(data["axis"]).to_lower()
			var val = float(data["value"])
			if axis == "x" and grid_mgr.has_method("_on_slice_x_changed"):
				grid_mgr._on_slice_x_changed(val)
				return true
			elif axis == "y" and grid_mgr.has_method("_on_slice_y_changed"):
				grid_mgr._on_slice_y_changed(val)
				return true
			elif axis == "z" and grid_mgr.has_method("_on_slice_z_changed"):
				grid_mgr._on_slice_z_changed(val)
				return true
		return false

	elif action == "solve_puzzle":
		var grid_mgr = _find_grid_manager(root)
		if grid_mgr and grid_mgr.has_method("_reveal_model"):
			grid_mgr.boss_hp = 0
			grid_mgr._reveal_model()
			return true
		return false

	return "UNKNOWN_ACTION"

func _find_grid_manager(node: Node) -> Node:
	if node.name == "GridManager" or node.name == "VoxelLogic" or node.has_method("_check_win_condition") or (node.get_script() != null and node.get_script().resource_path.ends_with("GridManager.gd")):
		return node
	for child in node.get_children():
		var found = _find_grid_manager(child)
		if found:
			return found
	return null
