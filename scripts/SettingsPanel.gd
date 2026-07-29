extends Panel

@onready var close_button: Button = $CloseButton
@onready var fullscreen_check: CheckBox = $VBoxContainer/FullscreenCheck
@onready var volume_slider: HSlider = $VBoxContainer/VolumeSlider

var config: ConfigFile = ConfigFile.new()
const SETTINGS_FILE_PATH = "user://settings.cfg"

func _ready() -> void:
	close_button.pressed.connect(_on_close_pressed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	volume_slider.value_changed.connect(_on_volume_changed)

	_load_settings()

func _on_close_pressed() -> void:
	hide()
	_save_settings()

func _on_fullscreen_toggled(button_pressed: bool) -> void:
	if button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _on_volume_changed(value: float) -> void:
	var bus_index = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))

func _load_settings() -> void:
	if config.load(SETTINGS_FILE_PATH) == OK:
		var is_fullscreen = config.get_value("display", "fullscreen", false)
		fullscreen_check.button_pressed = is_fullscreen
		_on_fullscreen_toggled(is_fullscreen)

		var vol = config.get_value("audio", "master_volume", 1.0)
		volume_slider.value = vol
		_on_volume_changed(vol)
	else:
		# defaults
		volume_slider.value = 1.0
		fullscreen_check.button_pressed = false

func _save_settings() -> void:
	config.set_value("display", "fullscreen", fullscreen_check.button_pressed)
	config.set_value("audio", "master_volume", volume_slider.value)
	config.save(SETTINGS_FILE_PATH)
