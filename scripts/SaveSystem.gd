extends Node

var save_path = "user://save_data.json"
var _bridge = null

var save_data = {
	"completed_puzzles": [],
	"stars_earned": {},
	"best_times": {},
	"current_wave": 0,
	"settings": {
		"sfx_vol": 1.0,
		"bgm_vol": 1.0,
		"haptics": true
	}
}

func _ready() -> void:
	if OS.has_feature("web"):
		_bridge = get_node_or_null("/root/TestBridge")
	load_game()

func save_game() -> void:
	var json_string = JSON.stringify(save_data)
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()

	if OS.has_feature("web"):
		# Synchronize with Web LocalStorage using JavaScriptBridge
		var script = "window.localStorage.setItem('godot_save_data', '" + json_string.replace("'", "\\'") + "');"
		if JavaScriptBridge:
			JavaScriptBridge.eval(script)

func load_game() -> void:
	var web_data_found = false
	if OS.has_feature("web"):
		if JavaScriptBridge:
			var script = "window.localStorage.getItem('godot_save_data');"
			var result = JavaScriptBridge.eval(script)
			if typeof(result) == TYPE_STRING and result != "":
				var parsed = JSON.parse_string(result)
				if typeof(parsed) == TYPE_DICTIONARY:
					_merge_save_data(parsed)
					web_data_found = true

	if not web_data_found and FileAccess.file_exists(save_path):
		var file = FileAccess.open(save_path, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			var parsed = JSON.parse_string(content)
			if typeof(parsed) == TYPE_DICTIONARY:
				_merge_save_data(parsed)
			file.close()

func _merge_save_data(data: Dictionary) -> void:
	for key in save_data.keys():
		if data.has(key):
			if typeof(save_data[key]) == TYPE_DICTIONARY and typeof(data[key]) == TYPE_DICTIONARY:
				save_data[key].merge(data[key], true)
			else:
				save_data[key] = data[key]
