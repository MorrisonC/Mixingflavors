extends Node

var pool_size: int = 8
var sfx_pool: Array = []
var next_sfx_index: int = 0

var bgm_player: AudioStreamPlayer

var is_haptics_enabled: bool = true

func _ready() -> void:
	_init_pool()
	_init_bgm()

	var save_sys = get_node_or_null("/root/SaveSystem")
	if save_sys and save_sys.has_method("load_game"):
		if save_sys.save_data.has("settings"):
			var settings = save_sys.save_data["settings"]
			is_haptics_enabled = settings.get("haptics", true)

func _init_pool() -> void:
	for i in range(pool_size):
		var p = AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		sfx_pool.append(p)

func _init_bgm() -> void:
	bgm_player = AudioStreamPlayer.new()
	bgm_player.bus = "Master"
	add_child(bgm_player)

func play_sfx(stream: AudioStream) -> void:
	if not stream:
		return
	var player = sfx_pool[next_sfx_index]
	player.stream = stream
	player.play()
	next_sfx_index = (next_sfx_index + 1) % pool_size

func play_chisel_sfx() -> void:
	# Mock loading since actual files are not guaranteed to exist
	# var stream = load("res://assets/audio/chisel.ogg")
	# play_sfx(stream)
	trigger_haptic_light()

func play_error_sfx() -> void:
	# var stream = load("res://assets/audio/error.ogg")
	# play_sfx(stream)
	trigger_haptic_heavy()

func trigger_haptic_light() -> void:
	if is_haptics_enabled and (OS.get_name() == "Android" or OS.get_name() == "iOS"):
		Input.vibrate_handheld(50)

func trigger_haptic_heavy() -> void:
	if is_haptics_enabled and (OS.get_name() == "Android" or OS.get_name() == "iOS"):
		Input.vibrate_handheld(200)
