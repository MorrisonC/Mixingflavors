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

func play_chisel_sfx(combo: int = 0) -> void:
	trigger_haptic_light()

	var player = sfx_pool[next_sfx_index]
	# Simulated chisel sound (pitch bends upward based on combo)
	# Since there's no actual file loaded by default, we just modulate pitch of whatever is there,
	# or if we had a synth, we'd play it. We will just ensure the pitch scales up.
	# We cap the pitch scale at 2.0 to avoid ear-piercing frequencies
	var pitch = 1.0 + min(combo * 0.05, 1.0)
	player.pitch_scale = pitch
	# player.stream = load("res://assets/audio/chisel.ogg")
	# player.play()

	next_sfx_index = (next_sfx_index + 1) % pool_size

func play_error_sfx() -> void:
	trigger_haptic_heavy()

	var player = sfx_pool[next_sfx_index]
	player.pitch_scale = 0.5 # Deep error sound
	# player.stream = load("res://assets/audio/error.ogg")
	# player.play()

	next_sfx_index = (next_sfx_index + 1) % pool_size

func trigger_haptic_light() -> void:
	if is_haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(40)

func trigger_haptic_heavy() -> void:
	if is_haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(120)