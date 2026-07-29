extends Control

const GameManagerClass = preload("res://scripts/GameManager.gd")

@onready var play_button: Button = $VBoxContainer/PlayButton
@onready var editor_button: Button = $VBoxContainer/EditorButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	editor_button.pressed.connect(_on_editor_pressed)
	settings_button.pressed.connect(_on_settings_pressed)

func _on_play_pressed() -> void:
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.ESCAPE_GAUNTLET)

func _on_editor_pressed() -> void:
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.PUZZLE_EDITOR)

func _on_settings_pressed() -> void:
	# Show settings menu
	var settings_menu = get_node_or_null("SettingsPanel")
	if settings_menu:
		settings_menu.show()
