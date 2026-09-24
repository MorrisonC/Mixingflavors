extends Panel

signal closed
signal opened

@onready var close_button: Button = $CloseButton
@onready var fullscreen_check: CheckBox = $VBoxContainer/FullscreenCheck
@onready var volume_slider: HSlider = $VBoxContainer/VolumeSlider

var config: ConfigFile = ConfigFile.new()
var _modal_owner: Control = null
var _ready_complete: bool = false

const SETTINGS_FILE_PATH: String = "user://settings.cfg"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_button.pressed.connect(_on_close_pressed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	volume_slider.value_changed.connect(_on_volume_changed)
	visibility_changed.connect(_on_visibility_changed)
	_load_settings()
	_ready_complete = true


func show_modal(owner: Control = null) -> void:
	_modal_owner = owner
	show()
	opened.emit()
	call_deferred("focus_first_control")


func hide_modal() -> void:
	var was_visible: bool = visible
	hide()
	if was_visible:
		closed.emit()
	_save_settings()
	if is_instance_valid(_modal_owner) and _modal_owner.has_method("_focus_settings"):
		_modal_owner.call("_focus_settings")


func focus_first_control() -> void:
	if not visible or not is_inside_tree():
		return
	if is_instance_valid(fullscreen_check) and not fullscreen_check.disabled:
		fullscreen_check.grab_focus()
	elif is_instance_valid(volume_slider):
		volume_slider.grab_focus()


func _on_visibility_changed() -> void:
	if visible:
		call_deferred("focus_first_control")


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	hide_modal()
	get_viewport().set_input_as_handled()


func _on_close_pressed() -> void:
	hide_modal()


func _on_fullscreen_toggled(button_pressed: bool) -> void:
	if not _fullscreen_supported():
		if fullscreen_check.button_pressed:
			fullscreen_check.set_pressed_no_signal(false)
		return
	if button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_volume_changed(value: float) -> void:
	var bus_index: int = AudioServer.get_bus_index("Master")
	if bus_index < 0:
		return
	var safe_value: float = clampf(value, 0.0001, 1.0)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(safe_value))


func _load_settings() -> void:
	var loaded: bool = config.load(SETTINGS_FILE_PATH) == OK
	var is_fullscreen: bool = false
	var volume: float = 1.0
	if loaded:
		is_fullscreen = bool(config.get_value("display", "fullscreen", false))
		volume = float(config.get_value("audio", "master_volume", 1.0))

	if _fullscreen_supported():
		fullscreen_check.disabled = false
		fullscreen_check.tooltip_text = "Toggle fullscreen"
		fullscreen_check.button_pressed = is_fullscreen
		_on_fullscreen_toggled(is_fullscreen)
	else:
		# Web exports and headless test runs cannot safely call the native
		# window mode API. Keep the control visible but non-interactive.
		fullscreen_check.disabled = true
		fullscreen_check.button_pressed = false
		fullscreen_check.tooltip_text = "Fullscreen is unavailable in this environment"

	volume_slider.value = clampf(volume, 0.0, 1.0)
	_on_volume_changed(volume_slider.value)


func _save_settings() -> void:
	if not _ready_complete:
		return
	config.set_value("display", "fullscreen", fullscreen_check.button_pressed and _fullscreen_supported())
	config.set_value("audio", "master_volume", clampf(volume_slider.value, 0.0, 1.0))
	config.save(SETTINGS_FILE_PATH)


func _fullscreen_supported() -> bool:
	# The web DisplayServer does not expose the native window-mode API. Avoid
	# calling it there (and in headless tests), where it can log or crash.
	var server_name: String = DisplayServer.get_name()
	return not OS.has_feature("web") and server_name != "headless" and server_name != "web"


func _exit_tree() -> void:
	if _ready_complete:
		_save_settings()
