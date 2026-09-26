extends Node

const CHISEL_SFX: AudioStream = preload("res://assets/audio/kenney_interface_sounds/chisel.ogg")
const MARK_SFX: AudioStream = preload("res://assets/audio/kenney_interface_sounds/mark.ogg")
const ERROR_SFX: AudioStream = preload("res://assets/audio/kenney_interface_sounds/error.ogg")
const TOGGLE_SFX: AudioStream = preload("res://assets/audio/kenney_interface_sounds/toggle.ogg")
const VICTORY_SFX: AudioStream = preload("res://assets/audio/kenney_interface_sounds/victory.ogg")

@export_range(1, 32, 1) var pool_size: int = 8

var sfx_pool: Array[AudioStreamPlayer] = []
var next_sfx_index: int = 0
var bgm_player: AudioStreamPlayer
var is_haptics_enabled: bool = true

func _ready() -> void:
	_init_pool()
	_init_bgm()
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager and save_manager.has_method("get_settings"):
		var settings: Dictionary = save_manager.call("get_settings")
		is_haptics_enabled = bool(settings.get("haptics", true))
		var master_volume: float = clampf(float(settings.get("sfx_vol", 1.0)), 0.0, 1.0)
		var master_bus: int = AudioServer.get_bus_index("Master")
		if master_bus >= 0:
			AudioServer.set_bus_volume_db(master_bus, linear_to_db(maxf(master_volume, 0.0001)))

func _init_pool() -> void:
	for _index: int in range(pool_size):
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		add_child(player)
		sfx_pool.append(player)

func _init_bgm() -> void:
	bgm_player = AudioStreamPlayer.new()
	bgm_player.bus = &"Master"
	add_child(bgm_player)

func play_sfx(stream: AudioStream, pitch: float = 1.0) -> void:
	if not stream or sfx_pool.is_empty():
		return
	var player: AudioStreamPlayer = sfx_pool[next_sfx_index]
	player.stream = stream
	player.pitch_scale = clampf(pitch, 0.5, 2.0)
	player.play()
	next_sfx_index = (next_sfx_index + 1) % sfx_pool.size()

func play_chisel_sfx(combo: int = 0) -> void:
	trigger_haptic_light()
	play_sfx(CHISEL_SFX, 1.0 + minf(float(combo) * 0.05, 1.0))

func play_paint_sfx() -> void:
	play_sfx(MARK_SFX, 1.0)

func play_ui_click_sfx() -> void:
	play_sfx(TOGGLE_SFX, 1.0)


func play_menu_move_sfx() -> void:
	play_sfx(TOGGLE_SFX, 0.82)


func play_round_start_sfx() -> void:
	play_sfx(MARK_SFX, 1.18)


func play_combo_sfx(combo: int) -> void:
	play_sfx(CHISEL_SFX, 0.96 + minf(float(maxi(0, combo)) * 0.025, 0.32))


func play_victory_sfx() -> void:
	play_sfx(VICTORY_SFX, 1.0)

func play_error_sfx() -> void:
	trigger_haptic_heavy()
	play_sfx(ERROR_SFX, 1.0)

func trigger_haptic_light() -> void:
	if is_haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(40)

func trigger_haptic_heavy() -> void:
	if is_haptics_enabled and OS.has_feature("mobile"):
		Input.vibrate_handheld(120)
