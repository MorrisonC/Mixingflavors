extends Control

const GameManagerClass = preload("res://scripts/GameManager.gd")

@onready var play_button: Button = $VBoxContainer/PlayButton
@onready var editor_button: Button = $VBoxContainer/EditorButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	editor_button.pressed.connect(_on_editor_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	
	var select_btn = get_node_or_null("VBoxContainer/SelectButton")
	if select_btn:
		select_btn.pressed.connect(_on_select_pressed)
	var editor_btn = get_node_or_null("VBoxContainer/EditorButton")
	if editor_btn:
		editor_btn.queue_free()

	var title = get_node_or_null("Title")
	if title:
		title.pivot_offset = title.size / 2
		var tween = create_tween().set_loops()
		tween.tween_property(title, "scale", Vector2(1.05, 1.05), 1.0).set_trans(Tween.TRANS_SINE)
		tween.tween_property(title, "scale", Vector2(1.0, 1.0), 1.0).set_trans(Tween.TRANS_SINE)

func _on_play_pressed() -> void:
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.ESCAPE_GAUNTLET)

func _on_select_pressed() -> void:
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.PUZZLE_SELECTION)

func _on_editor_pressed() -> void:
	get_node("/root/GameManager").switch_mode(GameManagerClass.GameMode.PUZZLE_EDITOR)

func _on_settings_pressed() -> void:
	# Show settings menu
	var settings_menu = get_node_or_null("SettingsPanel")
	if settings_menu:
		settings_menu.show()
